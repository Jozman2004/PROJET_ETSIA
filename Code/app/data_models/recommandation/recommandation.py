# =============================================================
#  YANSNET — Modèle 6 : Recommandation de Contenu
#  Fichier  : recommandation/recommandation.py
#  Rôle     : Suggérer des posts et des utilisateurs à suivre
#             basé sur les interactions réelles (likes, follows)
#             stockées dans la base PostgreSQL.
#
#  Technologie : Collaborative Filtering (filtrage collaboratif)
#  - On calcule la similarité entre utilisateurs
#    selon leurs likes communs
#  - "Les étudiants qui ont liké les mêmes posts que toi
#     ont aussi liké ces autres posts → on te les recommande"
#
#  ⚠️  AVANT D'UTILISER CE FICHIER :
#      Définis les variables d'environnement YANSNET_DB_*
#      (voir .env.example à la racine du projet)
#
#  Auteur   : Équipe Data — GROUPE 15
# =============================================================

import os
import numpy as np
import pandas as pd
import psycopg2
from sklearn.metrics.pairwise import cosine_similarity

# -------------------------------------------------------------
# ⚙️  CONFIGURATION DB — Via variables d'environnement
# -------------------------------------------------------------
DB_CONFIG = {
    "host"    : "localhost",
    "port"    : 5432,
    "dbname"  : "yansnet_db",
    "user"    : "postgres",
    "password": "1234"
}
# -------------------------------------------------------------
# PARAMÈTRES DE RECOMMANDATION
# -------------------------------------------------------------
NB_USERS_SIMILAIRES  = 5   # Nombre d'utilisateurs similaires à considérer
NB_POSTS_RECOMMANDES = 10  # Nombre de posts à recommander
NB_USERS_RECOMMANDES = 5   # Nombre d'utilisateurs à recommander


# -------------------------------------------------------------
# FONCTION UTILITAIRE — Connexion à PostgreSQL
# -------------------------------------------------------------
def connecter_db():
    """
    Crée et retourne une connexion à la base PostgreSQL.
    Lève une exception claire si la connexion échoue.
    """
    if not DB_CONFIG["password"]:
        raise ConnectionError(
            "Variable d'environnement YANSNET_DB_PASSWORD non définie.\n"
            "   Définis-la avant de lancer le serveur :\n"
            "   export YANSNET_DB_PASSWORD=ton_mot_de_passe"
        )
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except psycopg2.OperationalError as e:
        raise ConnectionError(
            f" Impossible de se connecter à la base de données.\n"
            f"   Vérifie les paramètres dans DB_CONFIG.\n"
            f"   Erreur : {e}"
        )


# -------------------------------------------------------------
# FONCTION 1 — Charger la matrice utilisateur-post depuis la DB
# -------------------------------------------------------------
def charger_matrice_likes() -> pd.DataFrame:
    """
    Charge les données de likes depuis PostgreSQL et construit
    une matrice binaire utilisateur × post.

    Structure de la matrice :
        Lignes    = utilisateurs (user_id)
        Colonnes  = publications (post_id)
        Valeur    = 1 si l'utilisateur a liké ce post, 0 sinon

    Exemple :
                  post-A  post-B  post-C
        user-1      1       0       1
        user-2      0       1       1
        user-3      1       1       0

    Returns:
        pd.DataFrame : matrice binaire utilisateur × post
    """
    conn = connecter_db()
    try:
        # Récupère tous les likes depuis la table likes
        query = """
            SELECT
                l.user_id::text  AS user_id,
                l.post_id::text  AS post_id
            FROM likes l
            JOIN posts p ON p.id = l.post_id
            WHERE p.is_deleted = FALSE
            ORDER BY l.created_at DESC
            LIMIT 50000;
        """
        df_likes = pd.read_sql(query, conn)

        if df_likes.empty:
            print("  Aucun like trouvé en base. Matrice vide.")
            return pd.DataFrame()

        # Pivot : construction de la matrice binaire
        matrice = df_likes.pivot_table(
            index   ="user_id",
            columns ="post_id",
            aggfunc =lambda x: 1,
            fill_value=0
        )

        print(f"[OK] Matrice chargee : {matrice.shape[0]} utilisateurs x {matrice.shape[1]} posts")
        return matrice

    finally:
        conn.close()


# -------------------------------------------------------------
# FONCTION 2 — Trouver les utilisateurs les plus similaires
# -------------------------------------------------------------
def trouver_utilisateurs_similaires(user_id: str, matrice: pd.DataFrame) -> list:
    """
    Trouve les utilisateurs les plus similaires à user_id
    en utilisant la similarité cosinus sur leurs likes.

    Args:
        user_id (str) : UUID de l'utilisateur cible
        matrice (pd.DataFrame) : matrice binaire utilisateur × post

    Returns:
        list[str] : liste des user_id les plus similaires
                    (du plus similaire au moins similaire)
    """
    if user_id not in matrice.index:
        print(f"[WARN] Utilisateur {user_id} absent de la matrice.")
        return []

    # Vecteur de l'utilisateur cible (1 ligne = ses likes)
    vecteur_cible = matrice.loc[[user_id]].values

    # Similarité cosinus entre cet utilisateur et tous les autres
    similarites = cosine_similarity(vecteur_cible, matrice.values)[0]

    # Créer un Series user_id → score de similarité
    scores = pd.Series(similarites, index=matrice.index)

    # Exclure l'utilisateur lui-même + trier par score décroissant
    scores = scores.drop(user_id, errors="ignore")
    similaires = scores.sort_values(ascending=False).head(NB_USERS_SIMILAIRES)

    return similaires.index.tolist()


# -------------------------------------------------------------
# FONCTION 3 — Recommander des posts
# -------------------------------------------------------------
def recommander_posts(user_id: str, matrice: pd.DataFrame) -> list:
    """
    Recommande des posts à un utilisateur basé sur ce que
    ses utilisateurs similaires ont liké mais que lui n'a pas vu.

    Args:
        user_id (str)           : UUID de l'utilisateur
        matrice (pd.DataFrame)  : matrice binaire utilisateur × post

    Returns:
        list[str] : liste de post_id recommandés
    """
    if user_id not in matrice.index:
        return []

    # Posts déjà likés par l'utilisateur
    posts_deja_likes = set(matrice.columns[matrice.loc[user_id] == 1])

    # Utilisateurs similaires
    similaires = trouver_utilisateurs_similaires(user_id, matrice)
    if not similaires:
        return []

    # Agréger les likes des utilisateurs similaires
    scores_posts = matrice.loc[similaires].sum(axis=0)

    # Exclure les posts déjà vus par l'utilisateur
    scores_posts = scores_posts.drop(list(posts_deja_likes), errors="ignore")

    # Trier par score décroissant → posts les plus likés par les similaires
    posts_recommandes = scores_posts.sort_values(ascending=False).head(NB_POSTS_RECOMMANDES)

    return posts_recommandes.index.tolist()


# -------------------------------------------------------------
# FONCTION 4 — Recommander des utilisateurs à suivre
# -------------------------------------------------------------
def recommander_utilisateurs(user_id: str, matrice: pd.DataFrame) -> list:
    """
    Recommande des utilisateurs à suivre basé sur les follows
    des utilisateurs similaires (amis d'amis).

    Args:
        user_id (str)           : UUID de l'utilisateur
        matrice (pd.DataFrame)  : matrice binaire utilisateur × post

    Returns:
        list[dict] : liste d'utilisateurs recommandés avec infos
            [{"user_id": "...", "full_name": "...", "avatar_url": "..."}]
    """
    similaires = trouver_utilisateurs_similaires(user_id, matrice)
    if not similaires:
        return []

    conn = connecter_db()
    try:
        # Récupérer les gens que les similaires suivent
        # mais que user_id ne suit pas encore
        query = """
            SELECT DISTINCT
                u.id::text       AS user_id,
                u.full_name,
                u.avatar_url,
                u.promotion,
                u.filiere,
                COUNT(f.follower_id) AS nb_followers_communs
            FROM follows f
            JOIN users u ON u.id = f.following_id
            WHERE
                f.follower_id = ANY(%s::uuid[])
                AND f.following_id != %s::uuid
                AND f.following_id NOT IN (
                    SELECT following_id FROM follows
                    WHERE follower_id = %s::uuid
                )
                AND u.is_active = TRUE
            GROUP BY u.id, u.full_name, u.avatar_url, u.promotion, u.filiere
            ORDER BY nb_followers_communs DESC
            LIMIT %s;
        """
        df = pd.read_sql(
            query, conn,
            params=(similaires, user_id, user_id, NB_USERS_RECOMMANDES)
        )

        return df.to_dict(orient="records")

    finally:
        conn.close()


# -------------------------------------------------------------
# FONCTION PRINCIPALE — Point d'entrée pour l'API Flask
# -------------------------------------------------------------
def obtenir_recommandations(user_id: str) -> dict:
    """
    Fonction principale appelée par l'API Flask.
    Retourne posts ET utilisateurs recommandés pour un user.

    Args:
        user_id (str) : UUID de l'utilisateur connecté

    Returns:
        dict: {
            "user_id"              : str,
            "posts_recommandes"    : list[str],   ← liste de post_id
            "utilisateurs_suggeres": list[dict],  ← liste d'utilisateurs
            "nb_posts"             : int,
            "nb_utilisateurs"      : int
        }

    Exemple d'utilisation depuis l'API :
        resultat = obtenir_recommandations("550e8400-e29b-41d4-a716-446655440000")
        print(resultat["posts_recommandes"])
        print(resultat["utilisateurs_suggeres"])
    """
    import re
    if not re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', user_id, re.I):
        return {
            "user_id": user_id,
            "erreur" : "user_id invalide — format UUID attendu",
            "posts_recommandes"    : [],
            "utilisateurs_suggeres": []
        }

    try:
        matrice = charger_matrice_likes()

        if matrice.empty:
            return {
                "user_id"              : user_id,
                "posts_recommandes"    : [],
                "utilisateurs_suggeres": [],
                "nb_posts"             : 0,
                "nb_utilisateurs"      : 0,
                "message"              : "Pas assez de données pour recommander"
            }

        # Générer les recommandations
        posts    = recommander_posts(user_id, matrice)
        users    = recommander_utilisateurs(user_id, matrice)

        return {
            "user_id"              : user_id,
            "posts_recommandes"    : posts,
            "utilisateurs_suggeres": users,
            "nb_posts"             : len(posts),
            "nb_utilisateurs"      : len(users)
        }

    except ConnectionError as e:
        return {
            "user_id": user_id,
            "erreur" : str(e),
            "posts_recommandes"    : [],
            "utilisateurs_suggeres": []
        }
    except Exception as e:
        return {
            "user_id": user_id,
            "erreur" : f"Erreur inattendue : {str(e)}",
            "posts_recommandes"    : [],
            "utilisateurs_suggeres": []
        }
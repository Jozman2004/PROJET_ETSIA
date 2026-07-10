# =============================================================
#  YANSNET — Test du Modèle 6 : Recommandation de Contenu
#  Fichier  : recommandation/test_recommandation.py
#
#  Ce fichier teste le modèle de 2 façons :
#  1. Avec des DONNÉES FICTIVES (sans DB) → toujours fonctionnel
#  2. Avec la VRAIE DB PostgreSQL          → nécessite connexion
#
#  Comment lancer :
#      cd moderation_backend/data_models/recommandation
#      python test_recommandation.py
# =============================================================

import pandas as pd
import numpy as np
from recommandation import (
    trouver_utilisateurs_similaires,
    recommander_posts,
    obtenir_recommandations,
    DB_CONFIG
)

# Couleurs terminal
VERT  = "\033[92m"
ROUGE = "\033[91m"
JAUNE = "\033[93m"
BLEU  = "\033[94m"
RESET = "\033[0m"
GRAS  = "\033[1m"

def separateur(titre):
    print(f"\n{BLEU}{GRAS}{'='*60}{RESET}")
    print(f"{BLEU}{GRAS}  {titre}{RESET}")
    print(f"{BLEU}{GRAS}{'='*60}{RESET}")


# ─────────────────────────────────────────────────────────────
# CONSTRUCTION D'UNE MATRICE FICTIVE POUR LES TESTS
# Simule ce que la DB retournerait
# ─────────────────────────────────────────────────────────────

# Utilisateurs fictifs (simulant des étudiants UCAC-ICAM)
USERS = {
    "user-alice"  : "Alice Ngo (X2029, GI)",
    "user-bob"    : "Bob Maza (X2028, GL)",
    "user-carole" : "Carole Tsa (X2029, GI)",
    "user-david"  : "David Ebé (X2027, Réseau)",
    "user-emma"   : "Emma Fon (X2029, GI)",
    "user-frank"  : "Frank Kwa (X2028, GL)",
}

# Posts fictifs
POSTS = [f"post-{i:03d}" for i in range(1, 16)]  # post-001 à post-015

# Matrice binaire fictive : qui a liké quoi
# 1 = liké, 0 = pas liké
LIKES_FICTIFS = pd.DataFrame([
    #         p01 p02 p03 p04 p05 p06 p07 p08 p09 p10 p11 p12 p13 p14 p15
    [          1,  1,  0,  1,  0,  1,  0,  0,  1,  0,  1,  0,  0,  1,  0],  # alice
    [          1,  1,  1,  0,  0,  1,  1,  0,  1,  0,  0,  1,  0,  0,  0],  # bob
    [          1,  1,  0,  1,  0,  1,  0,  1,  1,  0,  1,  0,  1,  1,  0],  # carole
    [          0,  0,  1,  0,  1,  0,  1,  1,  0,  1,  0,  1,  0,  0,  1],  # david
    [          0,  0,  1,  0,  1,  0,  1,  0,  0,  1,  0,  1,  0,  0,  1],  # emma
    [          1,  0,  0,  0,  0,  1,  0,  0,  1,  0,  0,  0,  0,  1,  0],  # frank
],
    index  =list(USERS.keys()),
    columns=POSTS
)


# ─────────────────────────────────────────────────────────────
# TEST 1 — Affichage de la matrice
# ─────────────────────────────────────────────────────────────
separateur("TEST 1 — Matrice utilisateur × post (données fictives)")

print(f"\n  {GRAS}Matrice binaire des likes :{RESET}")
print(f"  (1 = liké, 0 = pas liké)\n")
print(LIKES_FICTIFS.to_string())


# ─────────────────────────────────────────────────────────────
# TEST 2 — Utilisateurs similaires
# ─────────────────────────────────────────────────────────────
separateur("TEST 2 — Utilisateurs similaires")

utilisateurs_a_tester = ["user-alice", "user-david", "user-frank"]

for user_id in utilisateurs_a_tester:
    similaires = trouver_utilisateurs_similaires(user_id, LIKES_FICTIFS)
    nom = USERS[user_id]
    print(f"\n  👤 {GRAS}{nom}{RESET}")
    print(f"     Utilisateurs similaires (par ordre de proximité) :")
    for sim in similaires:
        print(f"     → {USERS.get(sim, sim)}")


# ─────────────────────────────────────────────────────────────
# TEST 3 — Posts recommandés
# ─────────────────────────────────────────────────────────────
separateur("TEST 3 — Posts recommandés")

for user_id in utilisateurs_a_tester:
    posts_rec = recommander_posts(user_id, LIKES_FICTIFS)
    nom = USERS[user_id]

    # Posts déjà likés
    deja_likes = LIKES_FICTIFS.columns[LIKES_FICTIFS.loc[user_id] == 1].tolist()

    print(f"\n   {GRAS}{nom}{RESET}")
    print(f"     Posts déjà likés    : {', '.join(deja_likes)}")
    print(f"     Posts recommandés   : {VERT}{', '.join(posts_rec) if posts_rec else 'aucun'}{RESET}")


# ─────────────────────────────────────────────────────────────
# TEST 4 — Cas limite : nouvel utilisateur sans likes
# ─────────────────────────────────────────────────────────────
separateur("TEST 4 — Nouvel utilisateur sans aucun like")

# Ajout d'un utilisateur vide
LIKES_FICTIFS_AVEC_NOUVEAU = LIKES_FICTIFS.copy()
LIKES_FICTIFS_AVEC_NOUVEAU.loc["user-nouveau"] = 0

similaires_nouveau = trouver_utilisateurs_similaires("user-nouveau", LIKES_FICTIFS_AVEC_NOUVEAU)
posts_nouveau      = recommander_posts("user-nouveau", LIKES_FICTIFS_AVEC_NOUVEAU)

print(f"\n  👤 {GRAS}Nouvel étudiant (0 like){RESET}")
print(f"     Similaires trouvés : {similaires_nouveau if similaires_nouveau else JAUNE + 'aucun (cold start)' + RESET}")
print(f"     Posts recommandés  : {posts_nouveau if posts_nouveau else JAUNE + 'aucun (cold start)' + RESET}")
print(f"\n  {JAUNE}  Cas Cold Start : le nouvel utilisateur n'a aucune interaction.")
print(f"     Solution : lui proposer les posts les plus likés globalement{RESET}")

# Fallback cold start : top posts globaux
top_posts = LIKES_FICTIFS.sum(axis=0).sort_values(ascending=False).head(5)
print(f"\n   Top 5 posts les plus populaires (fallback cold start) :")
for post, score in top_posts.items():
    print(f"     → {post} : {int(score)} likes")


# ─────────────────────────────────────────────────────────────
# TEST 5 — Connexion à la vraie DB (optionnel)
# ─────────────────────────────────────────────────────────────
separateur("TEST 5 — Connexion à la vraie DB PostgreSQL")

print(f"\n  {JAUNE}Configuration actuelle :{RESET}")
print(f"     host   : {DB_CONFIG['host']}")
print(f"     port   : {DB_CONFIG['port']}")
print(f"     dbname : {DB_CONFIG['dbname']}")
print(f"     user   : {DB_CONFIG['user']}")
print(f"     password: {'(défini)' if DB_CONFIG['password'] else '(non défini)'}")

print(f"\n  {JAUNE}  Pour tester avec la vraie DB :{RESET}")
print(f"     1. Définis les variables d'environnement YANSNET_DB_*")
print(f"        (voir .env.example à la racine du projet)")
print(f"     2. Décommente les 3 lignes ci-dessous")
print()

user_id_reel = "b4b53303-4ae6-41dd-9fbc-f397fb0d3d70"
resultat = obtenir_recommandations(user_id_reel)
print(resultat)

print(f"\n{VERT}{GRAS} Tous les tests terminés !{RESET}\n")
# =============================================================
#  YANSNET — Modèle 5 : Détection Spam / Flood
#  Fichier  : spam/spam.py
#  Rôle     : Détecter les comportements anormaux d'un utilisateur
#             (trop de posts, trop de likes, trop de DM en peu de temps)
#             en combinant des règles métier + un modèle sklearn
#             (Isolation Forest = détection d'anomalies)
#
#  Différence avec les autres modèles :
#  - Pas de HuggingFace ici
#  - On analyse le COMPORTEMENT (fréquence d'actions)
#    et non le CONTENU (texte/image)
#  - On génère notre propre dataset synthétique pour entraîner
#
#  Auteur   : Équipe Data — GROUPE 15
# =============================================================

import numpy as np
import joblib
import os
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler

# -------------------------------------------------------------
# CHEMINS DE SAUVEGARDE DES MODÈLES ENTRAÎNÉS
# -------------------------------------------------------------
DOSSIER      = os.path.dirname(os.path.abspath(__file__))
CHEMIN_MODEL = os.path.join(DOSSIER, "saved_spam_model.pkl")
CHEMIN_SCALER= os.path.join(DOSSIER, "saved_spam_scaler.pkl")

# -------------------------------------------------------------
# SEUILS DE RÈGLES MÉTIER (vérification rapide avant le ML)
# -------------------------------------------------------------
# Ces règles bloquent immédiatement les cas évidents
# sans même appeler le modèle ML
REGLES = {
    "max_posts_par_minute"     : 3,    # Max 3 publications par minute
    "max_likes_par_minute"     : 20,   # Max 20 likes par minute
    "max_dm_par_minute"        : 5,    # Max 5 DM par minute
    "max_commentaires_par_minute": 10, # Max 10 commentaires par minute
    "max_follows_par_minute"   : 15,   # Max 15 abonnements par minute
}


# -------------------------------------------------------------
# GÉNÉRATION DU DATASET SYNTHÉTIQUE
# -------------------------------------------------------------
def generer_dataset(n_normaux=300, n_spammeurs=80, seed=42):
    """
    Génère un dataset fictif de comportements utilisateurs.
    Chaque ligne = comportement d'un utilisateur sur 1 minute.

    Features (colonnes) :
        - posts_par_min       : nombre de publications
        - likes_par_min       : nombre de likes
        - dm_par_min          : nombre de messages privés
        - comments_par_min    : nombre de commentaires
        - follows_par_min     : nombre d'abonnements
        - ratio_actions_uniques: proportion d'actions vers des cibles différentes
                                 (0.1 = même cible répétée = suspect)

    Returns:
        X (np.array): features
        y (np.array): labels 0=normal, 1=spam
    """
    np.random.seed(seed)

    # Comportements NORMAUX
    normaux = np.column_stack([
        np.random.randint(0, 3,  n_normaux),   # posts_par_min       [0-2]
        np.random.randint(0, 15, n_normaux),   # likes_par_min       [0-14]
        np.random.randint(0, 4,  n_normaux),   # dm_par_min          [0-3]
        np.random.randint(0, 8,  n_normaux),   # comments_par_min    [0-7]
        np.random.randint(0, 10, n_normaux),   # follows_par_min     [0-9]
        np.random.uniform(0.6, 1.0, n_normaux) # ratio_uniques       [60-100%]
    ])

    # Comportements SPAMMEURS / BOTS
    spammeurs = np.column_stack([
        np.random.randint(5, 30,  n_spammeurs),   # posts_par_min      [5-29]
        np.random.randint(30, 100, n_spammeurs),  # likes_par_min      [30-99]
        np.random.randint(10, 50,  n_spammeurs),  # dm_par_min         [10-49]
        np.random.randint(15, 60,  n_spammeurs),  # comments_par_min   [15-59]
        np.random.randint(20, 80,  n_spammeurs),  # follows_par_min    [20-79]
        np.random.uniform(0.0, 0.3, n_spammeurs)  # ratio_uniques      [0-30%]
    ])

    X = np.vstack([normaux, spammeurs])
    y = np.array([0]*n_normaux + [1]*n_spammeurs)

    return X, y


# -------------------------------------------------------------
# ENTRAÎNEMENT DU MODÈLE
# -------------------------------------------------------------
def entrainer_modele():
    """
    Génère le dataset synthétique, entraîne l'Isolation Forest
    et sauvegarde le modèle + scaler sur disque.

    Isolation Forest = algorithme de détection d'anomalies :
    - Entraîné uniquement sur les comportements normaux
    - Détecte automatiquement ce qui s'écarte de la normale
    - Pas besoin d'exemples labellisés de spammeurs

    Returns:
        model  : IsolationForest entraîné
        scaler : StandardScaler ajusté
    """
    print("[INFO] Generation du dataset synthetique...")
    X, y = generer_dataset()

    # On entraîne UNIQUEMENT sur les normaux (Isolation Forest)
    X_normaux = X[y == 0]

    print("[INFO] Normalisation des features...")
    scaler = StandardScaler()
    X_normaux_scaled = scaler.fit_transform(X_normaux)

    print("[INFO] Entrainement du modele Isolation Forest...")
    model = IsolationForest(
        n_estimators=100,      # 100 arbres de décision
        contamination=0.05,    # On s'attend à ~5% d'anomalies
        random_state=42
    )
    model.fit(X_normaux_scaled)

    # Sauvegarde sur disque
    joblib.dump(model,  CHEMIN_MODEL)
    joblib.dump(scaler, CHEMIN_SCALER)
    print(f"[OK] Modele sauvegarde dans : {DOSSIER}")

    return model, scaler


# -------------------------------------------------------------
# CHARGEMENT OU ENTRAÎNEMENT AUTOMATIQUE
# -------------------------------------------------------------
if os.path.exists(CHEMIN_MODEL) and os.path.exists(CHEMIN_SCALER):
    print("[INFO] Chargement du modele spam existant...")
    spam_model  = joblib.load(CHEMIN_MODEL)
    spam_scaler = joblib.load(CHEMIN_SCALER)
    print("[OK] Modele spam charge !")
else:
    print("[WARN] Aucun modele trouve -- entrainement en cours...")
    spam_model, spam_scaler = entrainer_modele()


# -------------------------------------------------------------
# FONCTION 1 — Vérification par règles métier (rapide)
# -------------------------------------------------------------
def verifier_regles(comportement: dict) -> dict:
    """
    Vérifie les règles métier simples AVANT le modèle ML.
    Si une règle est violée → spam immédiat, pas besoin de ML.

    Args:
        comportement (dict): {
            "posts_par_min"      : int,
            "likes_par_min"      : int,
            "dm_par_min"         : int,
            "comments_par_min"   : int,
            "follows_par_min"    : int,
        }

    Returns:
        dict: {"spam": bool, "raison": str | None}
    """
    verifications = [
        ("posts_par_min",       "max_posts_par_minute",       "Trop de publications"),
        ("likes_par_min",       "max_likes_par_minute",       "Trop de likes"),
        ("dm_par_min",          "max_dm_par_minute",          "Trop de messages privés"),
        ("comments_par_min",    "max_commentaires_par_minute","Trop de commentaires"),
        ("follows_par_min",     "max_follows_par_minute",     "Trop d'abonnements"),
    ]

    for champ, regle, message in verifications:
        valeur = comportement.get(champ, 0)
        limite = REGLES[regle]
        if valeur > limite:
            return {
                "spam"  : True,
                "raison": f"{message} ({valeur} > limite {limite}/min)"
            }

    return {"spam": False, "raison": None}


# -------------------------------------------------------------
# FONCTION 2 — Détection complète (règles + ML)
# -------------------------------------------------------------
def detecter_spam(comportement: dict) -> dict:
    """
    Détecte si le comportement d'un utilisateur est du spam.
    Combine règles métier (rapides) + Isolation Forest (ML).

    Args:
        comportement (dict): {
            "posts_par_min"        : int,
            "likes_par_min"        : int,
            "dm_par_min"           : int,
            "comments_par_min"     : int,
            "follows_par_min"      : int,
            "ratio_actions_uniques": float  ← entre 0.0 et 1.0
        }

    Returns:
        dict: {
            "est_spam"        : bool,
            "methode_detection": "regles" | "ml" | None,
            "raison"          : str,
            "score_anomalie"  : float,   ← score ML (plus c'est négatif = plus suspect)
            "niveau"          : "OK" | "SUSPECT" | "SPAM"
        }

    Exemples:
        detecter_spam({"posts_par_min": 1, "likes_par_min": 5, ...})
        # {"est_spam": False, "niveau": "OK", ...}

        detecter_spam({"posts_par_min": 20, "likes_par_min": 80, ...})
        # {"est_spam": True, "niveau": "SPAM", "methode_detection": "regles", ...}
    """

    # --- ÉTAPE 1 : vérification règles métier ---
    check_regles = verifier_regles(comportement)
    if check_regles["spam"]:
        return {
            "est_spam"         : True,
            "methode_detection": "regles",
            "raison"           : check_regles["raison"],
            "score_anomalie"   : -1.0,
            "niveau"           : "SPAM"
        }

    # --- ÉTAPE 2 : vérification ML (Isolation Forest) ---
    features = np.array([[
        comportement.get("posts_par_min",         0),
        comportement.get("likes_par_min",         0),
        comportement.get("dm_par_min",            0),
        comportement.get("comments_par_min",      0),
        comportement.get("follows_par_min",       0),
        comportement.get("ratio_actions_uniques", 1.0),
    ]])

    features_scaled = spam_scaler.transform(features)

    # score_samples : plus c'est négatif = plus c'est une anomalie
    score = spam_model.score_samples(features_scaled)[0]

    # predict : -1 = anomalie (spam), 1 = normal
    prediction = spam_model.predict(features_scaled)[0]

    est_spam = prediction == -1

    if est_spam:
        niveau = "SPAM"
        raison = f"Comportement anormal détecté par le modèle ML (score: {round(score, 3)})"
    elif score < -0.3:
        niveau = "SUSPECT"
        raison = f"Comportement légèrement suspect (score: {round(score, 3)})"
        est_spam = False
    else:
        niveau = "OK"
        raison = "Comportement normal"

    return {
        "est_spam"         : est_spam,
        "methode_detection": "ml" if est_spam else None,
        "raison"           : raison,
        "score_anomalie"   : round(score, 4),
        "niveau"           : niveau
    }
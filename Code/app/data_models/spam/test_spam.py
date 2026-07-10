# =============================================================
#  YANSNET — Test du Modèle 5 : Détection Spam / Flood
#  Fichier  : spam/test_spam.py
#
#  Comment lancer :
#      cd moderation_backend/data_models/spam
#      python test_spam.py
# =============================================================

from spam import detecter_spam, entrainer_modele

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

def afficher_resultat(label, comportement, resultat):
    couleur = ROUGE if resultat["est_spam"] else (JAUNE if resultat["niveau"] == "SUSPECT" else VERT)
    icone   = "🔴" if resultat["est_spam"] else ("🟡" if resultat["niveau"] == "SUSPECT" else "🟢")
    print(f"\n  {icone} {GRAS}{label}{RESET}")
    print(f"     Posts/min    : {comportement.get('posts_par_min', 0)}")
    print(f"     Likes/min    : {comportement.get('likes_par_min', 0)}")
    print(f"     DM/min       : {comportement.get('dm_par_min', 0)}")
    print(f"     Comments/min : {comportement.get('comments_par_min', 0)}")
    print(f"     Follows/min  : {comportement.get('follows_par_min', 0)}")
    print(f"     Ratio uniques: {comportement.get('ratio_actions_uniques', 1.0):.0%}")
    print(f"     ─────────────────────────────────")
    print(f"     Niveau       : {couleur}{GRAS}{resultat['niveau']}{RESET}")
    print(f"     Spam détecté : {couleur}{GRAS}{'OUI ⚠️' if resultat['est_spam'] else 'NON ✅'}{RESET}")
    print(f"     Méthode      : {resultat['methode_detection'] or '—'}")
    print(f"     Score ML     : {resultat['score_anomalie']}")
    print(f"     Raison       : {resultat['raison']}")


# ─────────────────────────────────────────────────────────────
# TEST 1 — Comportements normaux
# ─────────────────────────────────────────────────────────────
separateur("TEST 1 — Comportements normaux (pas de spam attendu)")

cas_normaux = [
    ("Étudiant actif normal", {
        "posts_par_min"        : 1,
        "likes_par_min"        : 8,
        "dm_par_min"           : 2,
        "comments_par_min"     : 4,
        "follows_par_min"      : 3,
        "ratio_actions_uniques": 0.90
    }),
    ("Étudiant peu actif", {
        "posts_par_min"        : 0,
        "likes_par_min"        : 2,
        "dm_par_min"           : 1,
        "comments_par_min"     : 1,
        "follows_par_min"      : 0,
        "ratio_actions_uniques": 1.0
    }),
    ("Étudiant très actif mais légit", {
        "posts_par_min"        : 2,
        "likes_par_min"        : 12,
        "dm_par_min"           : 3,
        "comments_par_min"     : 7,
        "follows_par_min"      : 8,
        "ratio_actions_uniques": 0.75
    }),
]

for label, comportement in cas_normaux:
    resultat = detecter_spam(comportement)
    afficher_resultat(label, comportement, resultat)


# ─────────────────────────────────────────────────────────────
# TEST 2 — Spam détecté par les RÈGLES (cas évidents)
# ─────────────────────────────────────────────────────────────
separateur("TEST 2 — Spam évident détecté par les règles métier")

cas_spam_regles = [
    ("Bot qui publie en masse", {
        "posts_par_min"        : 25,
        "likes_par_min"        : 5,
        "dm_par_min"           : 1,
        "comments_par_min"     : 2,
        "follows_par_min"      : 2,
        "ratio_actions_uniques": 0.50
    }),
    ("Bot qui like tout en masse", {
        "posts_par_min"        : 0,
        "likes_par_min"        : 75,
        "dm_par_min"           : 0,
        "comments_par_min"     : 0,
        "follows_par_min"      : 0,
        "ratio_actions_uniques": 0.10
    }),
    ("Bot qui envoie des DM en masse", {
        "posts_par_min"        : 0,
        "likes_par_min"        : 1,
        "dm_par_min"           : 40,
        "comments_par_min"     : 0,
        "follows_par_min"      : 0,
        "ratio_actions_uniques": 0.05
    }),
    ("Bot follow/unfollow", {
        "posts_par_min"        : 0,
        "likes_par_min"        : 2,
        "dm_par_min"           : 0,
        "comments_par_min"     : 1,
        "follows_par_min"      : 60,
        "ratio_actions_uniques": 0.08
    }),
]

for label, comportement in cas_spam_regles:
    resultat = detecter_spam(comportement)
    afficher_resultat(label, comportement, resultat)


# ─────────────────────────────────────────────────────────────
# TEST 3 — Spam détecté par le MODÈLE ML (cas subtils)
# ─────────────────────────────────────────────────────────────
separateur("TEST 3 — Spam subtil détecté par le modèle ML")

cas_spam_ml = [
    ("Bot discret mais suspect (toutes actions légèrement élevées)", {
        "posts_par_min"        : 4,
        "likes_par_min"        : 18,
        "dm_par_min"           : 6,
        "comments_par_min"     : 12,
        "follows_par_min"      : 14,
        "ratio_actions_uniques": 0.15   # Toujours les mêmes cibles
    }),
    ("Bot qui répète les mêmes actions sur les mêmes profils", {
        "posts_par_min"        : 2,
        "likes_par_min"        : 16,
        "dm_par_min"           : 4,
        "comments_par_min"     : 9,
        "follows_par_min"      : 13,
        "ratio_actions_uniques": 0.08
    }),
]

for label, comportement in cas_spam_ml:
    resultat = detecter_spam(comportement)
    afficher_resultat(label, comportement, resultat)


# ─────────────────────────────────────────────────────────────
# TEST 4 — Réentraîner le modèle manuellement
# ─────────────────────────────────────────────────────────────
separateur("TEST 4 — Réentraînement du modèle")

print("\n Réentraînement forcé du modèle spam...")
entrainer_modele()
print(f"{VERT}{GRAS} Modèle réentraîné et sauvegardé avec succès !{RESET}")

print(f"\n{VERT}{GRAS} Tous les tests terminés !{RESET}\n")
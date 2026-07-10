# =============================================================
#  YANSNET — Test du Modèle 3 : Analyse Sentimentale
#  Fichier  : sentiment/test_sentiment.py
#  Rôle     : Tester les deux fonctions du modèle sentiment
#              avec des exemples concrets tirés du contexte UCAC-ICAM
#
#  Comment lancer :
#      cd moderation_backend/data_models/sentiment
#      python test_sentiment.py
# =============================================================

from sentiment import analyser_sentiment, analyser_utilisateur

# Couleurs pour le terminal
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

def afficher_resultat_simple(texte, resultat):
    couleur = ROUGE if resultat["label"] == "NEGATIVE" else (VERT if resultat["label"] == "POSITIVE" else JAUNE)
    print(f"\n Texte   : \"{texte}\"")
    print(f"   Label   : {couleur}{GRAS}{resultat['label']}{RESET}")
    print(f"    POS  : {resultat['score_pos']:.2%}")
    print(f"    NEU  : {resultat['score_neu']:.2%}")
    print(f"    NEG  : {resultat['score_neg']:.2%}")
    if resultat["en_detresse"]:
        print(f"   {ROUGE}{GRAS}  EN DÉTRESSE DÉTECTÉE{RESET}")
    else:
        print(f"   {VERT} Pas de détresse{RESET}")


# ─────────────────────────────────────────────────────────────
# TEST 1 — Analyse de textes individuels
# ─────────────────────────────────────────────────────────────
separateur("TEST 1 — Analyse de textes individuels")

textes_test = [
    # Posts positifs
    "Alhamdoulilah j'ai eu mon examen de maths ! trop content 🎉",
    "Super ambiance à la soirée COCFET hier soir, meilleurs souvenirs de l'ICAM",
    "Merci à tous mes amis de la minicité pour leur soutien, ça fait chaud au cœur",

    # Posts neutres
    "Les cours de GI X2029 reprennent lundi à 8h en salle B12",
    "Quelqu'un a vu le planning des examens de rattrapage ?",

    # Posts négatifs / en détresse
    "je suis épuisé, je dors plus depuis 3 jours à cause des examens",
    "à quoi ça sert vraiment tout ça... je comprends plus rien",
    "j'en peux plus, trop de pression, je tiens plus le coup",
    "encore une nuit blanche, je suis à bout",
]

for texte in textes_test:
    resultat = analyser_sentiment(texte)
    afficher_resultat_simple(texte, resultat)


# ─────────────────────────────────────────────────────────────
# TEST 2 — Analyse d'un utilisateur avec plusieurs posts
# ─────────────────────────────────────────────────────────────
separateur("TEST 2 — Utilisateur en état normal")

posts_normaux = [
    "Bonne journée à tous !",
    "Les cours se passent bien ce semestre",
    "Weekend sympa avec les amis de la résidence",
]

resultat_normal = analyser_utilisateur(posts_normaux)
print(f"\n👤 Score moyen négatif : {resultat_normal['score_moyen_negatif']:.2%}")
print(f"   Posts en détresse   : {resultat_normal['posts_negatifs']}/{len(posts_normaux)}")
print(f"   Niveau              : {VERT}{GRAS}{resultat_normal['niveau']}{RESET}")
print(f"   Alerte              : {' OUI' if resultat_normal['alerte'] else VERT + '✅ NON' + RESET}")


separateur("TEST 3 — Utilisateur en DÉTRESSE (alerte attendue)")

posts_detresse = [
    "je suis épuisé, je dors plus depuis 3 jours",
    "à quoi ça sert vraiment tout ça...",
    "j'en peux plus, trop de pression, je tiens plus le coup",
    "encore une nuit blanche, je suis à bout de tout",
]

resultat_detresse = analyser_utilisateur(posts_detresse)
print(f"\n Score moyen négatif : {resultat_detresse['score_moyen_negatif']:.2%}")
print(f"   Posts en détresse   : {resultat_detresse['posts_negatifs']}/{len(posts_detresse)}")

niveau = resultat_detresse['niveau']
couleur_niveau = ROUGE if niveau == "CRITIQUE" else (JAUNE if niveau == "ATTENTION" else VERT)
print(f"   Niveau              : {couleur_niveau}{GRAS}{niveau}{RESET}")
print(f"   Alerte              : {ROUGE + GRAS + '⚠️  OUI — ALERTER LE CONCIERGE' + RESET if resultat_detresse['alerte'] else VERT + '✅ NON' + RESET}")

print(f"\n   Détail par post :")
for i, detail in enumerate(resultat_detresse["details"], 1):
    icone = "🔴" if detail["en_detresse"] else "🟢"
    print(f"   {i}. {icone} [{detail['label']}] {detail['score_neg']:.2%} négatif — \"{detail['texte']}\"")


separateur("TEST 4 — Utilisateur en ATTENTION (alerte légère)")

posts_attention = [
    "bof, ça va pas trop en ce moment",
    "les cours sont vraiment difficiles cette semaine",
    "j'essaie de tenir mais c'est dur",
    "quand même content d'avoir fini les partiels",
]

resultat_attention = analyser_utilisateur(posts_attention)
print(f"\n👤 Score moyen négatif : {resultat_attention['score_moyen_negatif']:.2%}")
print(f"   Posts en détresse   : {resultat_attention['posts_negatifs']}/{len(posts_attention)}")
niveau = resultat_attention['niveau']
couleur_niveau = ROUGE if niveau == "CRITIQUE" else (JAUNE if niveau == "ATTENTION" else VERT)
print(f"   Niveau              : {couleur_niveau}{GRAS}{niveau}{RESET}")
print(f"   Alerte              : {ROUGE + GRAS + '  OUI' + RESET if resultat_attention['alerte'] else VERT + '✅ NON' + RESET}")


# ─────────────────────────────────────────────────────────────
# TEST 5 — Cas limites
# ─────────────────────────────────────────────────────────────
separateur("TEST 5 — Cas limites")

cas_limites = [
    "",                          # Texte vide
    "   ",                       # Texte avec espaces
    "lol mdr 😂😂",              # Argot/emojis
    "jsp",                       # Très court
]

for texte in cas_limites:
    resultat = analyser_sentiment(texte)
    afficher_resultat_simple(repr(texte), resultat)

print(f"\n{VERT}{GRAS} Tous les tests terminés !{RESET}\n")
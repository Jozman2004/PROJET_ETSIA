# =============================================================
#  YANSNET — Test du Modèle 4 : Détection de Harcèlement
#  Fichier  : harcelement/test_harcelement.py
#
#  Comment lancer :
#      cd moderation_backend/data_models/harcelement
#      python test_harcelement.py
# =============================================================

from harcelement import analyser_commentaire, analyser_harceleur

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

def afficher_commentaire(texte, resultat):
    couleur = ROUGE if resultat["est_harcelant"] else VERT
    icone   = "🔴" if resultat["est_harcelant"] else "🟢"
    print(f"\n  {icone} \"{texte}\"")
    print(f"     Label       : {couleur}{GRAS}{resultat['label']}{RESET}")
    print(f"     Score toxic : {resultat['score_toxic']:.2%}")
    print(f"     Harcelant   : {couleur}{GRAS}{'OUI ⚠️' if resultat['est_harcelant'] else 'NON ✅'}{RESET}")


# ─────────────────────────────────────────────────────────────
# TEST 1 — Commentaires individuels
# ─────────────────────────────────────────────────────────────
separateur("TEST 1 — Commentaires individuels")

commentaires_test = [
    # Commentaires normaux
    "Bon courage pour les examens !",
    "Je suis d'accord avec toi sur ce point",
    "Beau travail sur ce projet, bravo",

    # Commentaires limites
    "C'est pas vraiment ton meilleur post...",
    "Je comprends pas ton raisonnement franchement",

    # Commentaires harcelants
    "t'es vraiment nul, arrête de poster",
    "personne te supporte ici, dégage",
    "t'as aucun talent, laisse tomber",
    "vous êtes tous des idiots dans cette résidence",
]

print()
for texte in commentaires_test:
    resultat = analyser_commentaire(texte)
    afficher_commentaire(texte, resultat)


# ─────────────────────────────────────────────────────────────
# TEST 2 — Harceleur ciblant une seule victime
# ─────────────────────────────────────────────────────────────
separateur("TEST 2 — Harceleur ciblant une seule victime (alerte attendue)")

# Simulation : David harcèle Marie sur ses posts
commentaires_david = [
    {"texte": "t'es vraiment nulle arrête de poster", "cible_id": "user-marie-001"},
    {"texte": "personne t'aime ici",                  "cible_id": "user-marie-001"},
    {"texte": "tes photos sont laides comme toi",     "cible_id": "user-marie-001"},
    {"texte": "dégage de cette école",                "cible_id": "user-marie-001"},
]

resultat = analyser_harceleur(commentaires_david)

print(f"\n👤 Harceleur analysé : David")
print(f"   Total messages toxiques : {resultat['total_toxiques']}/{len(commentaires_david)}")
print(f"   Alerte : {ROUGE + GRAS + '⚠️  OUI — SUSPENDRE LE COMPTE' + RESET if resultat['alerte'] else VERT + '✅ NON' + RESET}")

if resultat["cibles_harcelees"]:
    print(f"\n    Cibles harcelées :")
    for cible in resultat["cibles_harcelees"]:
        detail = resultat["detail_par_cible"][cible]
        print(f"      → {cible}")
        print(f"         {detail['messages_toxiques']}/{detail['total_messages']} messages toxiques ({detail['ratio_toxique']:.0%})")


# ─────────────────────────────────────────────────────────────
# TEST 3 — Utilisateur normal avec quelques critiques
# ─────────────────────────────────────────────────────────────
separateur("TEST 3 — Utilisateur normal (pas d'alerte attendue)")

commentaires_normaux = [
    {"texte": "Je suis pas d'accord avec toi sur ça", "cible_id": "user-paul-002"},
    {"texte": "Bonne idée mais c'est perfectible",    "cible_id": "user-paul-002"},
    {"texte": "Intéressant comme point de vue",       "cible_id": "user-paul-002"},
]

resultat_normal = analyser_harceleur(commentaires_normaux)
print(f"\n👤 Utilisateur analysé : commentaires normaux")
print(f"   Total messages toxiques : {resultat_normal['total_toxiques']}/{len(commentaires_normaux)}")
print(f"   Alerte : {ROUGE + GRAS + '  OUI' + RESET if resultat_normal['alerte'] else VERT + '✅ NON — Comportement normal' + RESET}")


# ─────────────────────────────────────────────────────────────
# TEST 4 — Harceleur ciblant PLUSIEURS victimes
# ─────────────────────────────────────────────────────────────
separateur("TEST 4 — Harceleur ciblant plusieurs victimes")

commentaires_multi = [
    {"texte": "t'es nul arrête",              "cible_id": "user-marie-001"},
    {"texte": "personne t'aime",              "cible_id": "user-marie-001"},
    {"texte": "t'as aucun talent, laisse tomber", "cible_id": "user-marie-001"},
    {"texte": "toi aussi t'es inutile",       "cible_id": "user-paul-002"},
    {"texte": "dégage de l'ICAM",             "cible_id": "user-paul-002"},
    {"texte": "vous êtes nuls tous les deux", "cible_id": "user-paul-002"},
]

resultat_multi = analyser_harceleur(commentaires_multi)
print(f"\n👤 Harceleur ciblant plusieurs personnes")
print(f"   Total messages toxiques : {resultat_multi['total_toxiques']}/{len(commentaires_multi)}")
print(f"   Alerte : {ROUGE + GRAS + '  OUI' + RESET if resultat_multi['alerte'] else VERT + '✅ NON' + RESET}")

if resultat_multi["cibles_harcelees"]:
    print(f"\n    {len(resultat_multi['cibles_harcelees'])} cible(s) harcelée(s) :")
    for cible in resultat_multi["cibles_harcelees"]:
        detail = resultat_multi["detail_par_cible"][cible]
        print(f"      → {cible} : {detail['messages_toxiques']}/{detail['total_messages']} messages toxiques")


print(f"\n{VERT}{GRAS} Tous les tests terminés !{RESET}\n")
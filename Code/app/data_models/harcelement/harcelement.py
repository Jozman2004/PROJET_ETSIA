# =============================================================
#  YANSNET — Modèle 4 : Détection de Harcèlement
#  Fichier  : harcelement/harcelement.py
#  Rôle     : Détecter si un commentaire est harcelant ET
#             si un utilisateur harcèle une cible précise
#             en analysant ses commentaires dans le temps.
#
#  Différence avec la censure 
#  - Censure texte  → bloque UN message isolé avant publication
#  - Harcèlement    → détecte un PATTERN sur plusieurs messages
#                     vers une même cible (victime identifiée)
#
#  Auteur   : Équipe Data — GROUPE 15
# =============================================================

from transformers import pipeline
from collections import defaultdict

# -------------------------------------------------------------
# CHARGEMENT DU MODÈLE
# -------------------------------------------------------------
# Modèle pré-entraîné multilingue de détection de toxicité
# Aucun dataset nécessaire — déjà entraîné sur des données réelles
# Labels : "toxic" / "non-toxic"
# -------------------------------------------------------------

print("[INFO] Chargement du modele de detection de harcelement...")

from transformers import AutoTokenizer, AutoModelForSequenceClassification

_harcelement_tokenizer = AutoTokenizer.from_pretrained(
    "martin-ha/toxic-comment-model", use_fast=False
)
_harcelement_model_obj = AutoModelForSequenceClassification.from_pretrained(
    "martin-ha/toxic-comment-model"
)
harcelement_model = pipeline(
    "text-classification",
    model=_harcelement_model_obj,
    tokenizer=_harcelement_tokenizer,
    top_k=None
)

print("[OK] Modele harcelement charge !")

# -------------------------------------------------------------
# SEUILS DE DÉCISION
# -------------------------------------------------------------
SEUIL_TOXIQUE        = 0.75   # Score toxic au-dessus duquel un commentaire est harcelant
SEUIL_NB_MESSAGES    = 3      # Nombre de messages toxiques vers une cible pour déclencher alerte
SEUIL_RATIO_TOXIQUE  = 0.50   # Si + de 50% des messages vers une cible sont toxiques → alerte


# -------------------------------------------------------------
# FONCTION 1 — Analyser UN seul commentaire
# -------------------------------------------------------------
def analyser_commentaire(texte: str) -> dict:
    """
    Analyse si un commentaire est harcelant ou non.

    Args:
        texte (str): Le contenu du commentaire à analyser

    Returns:
        dict: {
            "label"      : "toxic" | "non-toxic",
            "score_toxic": float,
            "est_harcelant": bool
        }

    Exemple:
        res = analyser_commentaire("t'es nul et tu mérites rien")
        # {'label': 'toxic', 'score_toxic': 0.91, 'est_harcelant': True}
    """

    if not texte or not texte.strip():
        return {
            "label": "non-toxic",
            "score_toxic": 0.0,
            "est_harcelant": False
        }

    resultats = harcelement_model(texte[:512])[0]

    # Construire un dict label → score
    scores = {r['label'].lower(): r['score'] for r in resultats}
    score_toxic = scores.get("toxic", 0.0)
    label = "toxic" if score_toxic >= SEUIL_TOXIQUE else "non-toxic"

    return {
        "label": label,
        "score_toxic": round(score_toxic, 4),
        "est_harcelant": label == "toxic"
    }


# -------------------------------------------------------------
# FONCTION 2 — Analyser les commentaires d'un harceleur potentiel
#              vers une ou plusieurs cibles
# -------------------------------------------------------------
def analyser_harceleur(commentaires: list[dict]) -> dict:
    """
    Analyse une liste de commentaires d'un même utilisateur
    pour détecter s'il harcèle une ou plusieurs cibles.

    Args:
        commentaires (list[dict]): Liste de commentaires au format :
            [
                {
                    "texte"    : "t'es vraiment nul",
                    "cible_id" : "user-uuid-de-la-victime"
                },
                ...
            ]

    Returns:
        dict: {
            "alerte"          : bool,
            "cibles_harcelees": list  ← liste des user_id harcelés
            "detail_par_cible": dict  ← stats par cible
            "total_toxiques"  : int
        }

    Exemple:
        commentaires = [
            {"texte": "t'es nul", "cible_id": "user-123"},
            {"texte": "dégage", "cible_id": "user-123"},
            {"texte": "personne t'aime", "cible_id": "user-123"},
        ]
        res = analyser_harceleur(commentaires)
        # res["alerte"] = True
        # res["cibles_harcelees"] = ["user-123"]
    """

    if not commentaires:
        return {
            "alerte": False,
            "cibles_harcelees": [],
            "detail_par_cible": {},
            "total_toxiques": 0
        }

    # Grouper les commentaires par cible
    # { "user-123": [{"texte": ..., "toxic": True, "score": 0.91}, ...] }
    par_cible = defaultdict(list)

    total_toxiques = 0

    for com in commentaires:
        texte     = com.get("texte", "")
        cible_id  = com.get("cible_id", "inconnu")

        analyse = analyser_commentaire(texte)

        par_cible[cible_id].append({
            "texte"        : texte[:80] + "..." if len(texte) > 80 else texte,
            "est_harcelant": analyse["est_harcelant"],
            "score_toxic"  : analyse["score_toxic"]
        })

        if analyse["est_harcelant"]:
            total_toxiques += 1

    # Évaluer chaque cible
    cibles_harcelees  = []
    detail_par_cible  = {}

    for cible_id, messages in par_cible.items():
        total      = len(messages)
        nb_toxic   = sum(1 for m in messages if m["est_harcelant"])
        ratio      = nb_toxic / total if total > 0 else 0

        est_harcelee = (
            nb_toxic >= SEUIL_NB_MESSAGES or
            ratio >= SEUIL_RATIO_TOXIQUE
        )

        if est_harcelee:
            cibles_harcelees.append(cible_id)

        detail_par_cible[cible_id] = {
            "total_messages" : total,
            "messages_toxiques": nb_toxic,
            "ratio_toxique"  : round(ratio, 4),
            "est_harcelee"   : est_harcelee,
            "messages"       : messages
        }

    alerte = len(cibles_harcelees) > 0

    return {
        "alerte"          : alerte,
        "cibles_harcelees": cibles_harcelees,
        "detail_par_cible": detail_par_cible,
        "total_toxiques"  : total_toxiques
    }
# =============================================================
#  YANSNET — Modèle 3 : Analyse Sentimentale
#  Fichier  : sentiment/sentiment.py
#  Rôle     : Analyser le sentiment d'un texte (post ou commentaire)
#             et détecter si un utilisateur montre des signes de
#             détresse (dépression, surmenage) sur plusieurs jours.
#  Auteur   : Équipe Data — GROUPE 15
# =============================================================

from transformers import pipeline

# -------------------------------------------------------------
# CHARGEMENT DU MODÈLE
# -------------------------------------------------------------
# On utilise un modèle pré-entraîné multilingue (français inclus)
# cardiffnlp/twitter-xlm-roberta-base-sentiment
# Labels possibles : POSITIVE / NEUTRAL / NEGATIVE
# Avantage : comprend le français, l'argot, les abréviations
# Aucun dataset nécessaire — le modèle est déjà entraîné
# -------------------------------------------------------------

print("[INFO] Chargement du modele de sentiment...")

from transformers import AutoTokenizer, AutoModelForSequenceClassification

_sentiment_tokenizer = AutoTokenizer.from_pretrained(
    "cardiffnlp/twitter-xlm-roberta-base-sentiment", use_fast=False
)
_sentiment_model_obj = AutoModelForSequenceClassification.from_pretrained(
    "cardiffnlp/twitter-xlm-roberta-base-sentiment"
)
sentiment_model = pipeline(
    "text-classification",
    model=_sentiment_model_obj,
    tokenizer=_sentiment_tokenizer,
    top_k=None
)

print("[OK] Modele sentiment charge !")

# -------------------------------------------------------------
# SEUILS DE DÉCISION
# -------------------------------------------------------------
SEUIL_ALERTE = 0.70       # Score NÉGATIF au-dessus duquel un post est "en détresse"
SEUIL_CRITIQUE = 3        # Nombre de posts négatifs consécutifs pour déclencher une alerte


# -------------------------------------------------------------
# FONCTION 1 — Analyser UN seul texte
# -------------------------------------------------------------
def analyser_sentiment(texte: str) -> dict:
    """
    Analyse le sentiment d'un texte unique.

    Args:
        texte (str): Le contenu d'un post ou commentaire

    Returns:
        dict: {
            "label"     : "POSITIVE" | "NEUTRAL" | "NEGATIVE",
            "score_pos" : float,
            "score_neu" : float,
            "score_neg" : float,
            "en_detresse": bool   ← True si score négatif > SEUIL_ALERTE
        }

    Exemple d'utilisation:
        resultat = analyser_sentiment("je suis épuisé, plus rien ne va")
        print(resultat)
        # {'label': 'NEGATIVE', 'score_neg': 0.92, ..., 'en_detresse': True}
    """

    if not texte or not texte.strip():
        return {
            "label": "NEUTRAL",
            "score_pos": 0.0,
            "score_neu": 1.0,
            "score_neg": 0.0,
            "en_detresse": False
        }

    # Le modèle retourne une liste de listes :
    # [[{'label': 'positive', 'score': 0.02}, {'label': 'neutral', 'score': 0.06}, {'label': 'negative', 'score': 0.92}]]
    resultats = sentiment_model(texte[:512])[0]  # Limite à 512 tokens (limite du modèle)

    # On transforme en dictionnaire pour accéder facilement
    scores = {r['label'].upper(): r['score'] for r in resultats}

    score_pos = scores.get("POSITIVE", 0.0)
    score_neu = scores.get("NEUTRAL", 0.0)
    score_neg = scores.get("NEGATIVE", 0.0)

    # Le label dominant = celui avec le score le plus élevé
    label = max(scores, key=scores.get)

    # En détresse si le score négatif dépasse le seuil d'alerte
    en_detresse = score_neg >= SEUIL_ALERTE

    return {
        "label": label,
        "score_pos": round(score_pos, 4),
        "score_neu": round(score_neu, 4),
        "score_neg": round(score_neg, 4),
        "en_detresse": en_detresse
    }


# -------------------------------------------------------------
# FONCTION 2 — Analyser PLUSIEURS posts d'un même utilisateur
# -------------------------------------------------------------
def analyser_utilisateur(posts: list[str]) -> dict:
    """
    Analyse une liste de posts d'un utilisateur sur une période
    et détermine s'il faut envoyer une alerte aux modérateurs.

    Args:
        posts (list[str]): Liste des contenus textuels des posts récents
                           de l'utilisateur (du plus récent au plus ancien)

    Returns:
        dict: {
            "score_moyen_negatif" : float,   ← score négatif moyen sur tous les posts
            "posts_negatifs"      : int,     ← nombre de posts en détresse
            "alerte"              : bool,    ← True si l'utilisateur est en danger
            "niveau"              : str,     ← "OK" | "ATTENTION" | "CRITIQUE"
            "details"             : list     ← résultat de chaque post
        }

    Exemple d'utilisation:
        posts = [
            "je suis fatigué de tout",
            "encore une nuit sans dormir",
            "à quoi ça sert vraiment..."
        ]
        resultat = analyser_utilisateur(posts)
        print(resultat["alerte"])   # True
        print(resultat["niveau"])   # "CRITIQUE"
    """

    if not posts:
        return {
            "score_moyen_negatif": 0.0,
            "posts_negatifs": 0,
            "alerte": False,
            "niveau": "OK",
            "details": []
        }

    details = []
    total_score_negatif = 0.0
    posts_negatifs = 0

    for post in posts:
        analyse = analyser_sentiment(post)
        details.append({
            "texte": post[:80] + "..." if len(post) > 80 else post,
            "label": analyse["label"],
            "score_neg": analyse["score_neg"],
            "en_detresse": analyse["en_detresse"]
        })
        total_score_negatif += analyse["score_neg"]
        if analyse["en_detresse"]:
            posts_negatifs += 1

    score_moyen = total_score_negatif / len(posts)

    # Détermination du niveau d'alerte
    if posts_negatifs >= SEUIL_CRITIQUE or score_moyen >= 0.80:
        niveau = "CRITIQUE"
        alerte = True
    elif posts_negatifs >= 2 or score_moyen >= 0.60:
        niveau = "ATTENTION"
        alerte = True
    else:
        niveau = "OK"
        alerte = False

    return {
        "score_moyen_negatif": round(score_moyen, 4),
        "posts_negatifs": posts_negatifs,
        "alerte": alerte,
        "niveau": niveau,
        "details": details
    }
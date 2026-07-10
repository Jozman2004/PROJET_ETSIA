# =============================================================
#  YANSNET — Serveur Principal Data
#  Fichier  : app_data.py
#  Rôle     : Expose les 4 modèles IA en API Flask (port 5002)
#
#  Endpoints disponibles :
#   POST /sentiment          → Analyse sentimentale (1 texte)
#   POST /sentiment/user     → Analyse sentimentale (plusieurs posts)
#   POST /harcelement        → Détection harcèlement (1 commentaire)
#   POST /harcelement/user   → Détection harcèlement (série de commentaires)
#   POST /spam               → Détection spam/flood
#   GET  /recommandation/<user_id> → Recommandations posts + users
#   GET  /health             → Vérification que le serveur tourne
#
#  Comment lancer :
#      cd data_models
#      python app_data.py
#
#  Auteur   : Équipe Data — GROUPE 15
# =============================================================

import sys
import os

# Ajouter le dossier data_models au path Python
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from flask import Flask, request, jsonify
from flask_cors import CORS

# Import des 4 modèles
from sentiment.sentiment         import analyser_sentiment, analyser_utilisateur
from harcelement.harcelement     import analyser_commentaire, analyser_harceleur
from spam.spam                   import detecter_spam
from recommandation.recommandation import obtenir_recommandations

# -------------------------------------------------------------
# INITIALISATION DE L'APP FLASK
# -------------------------------------------------------------
app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024  # 2 Mo max par requête

CORS(app, origins=os.environ.get("YANSNET_CORS_ORIGINS", "*").split(","))

print("=" * 55)
print("  YANSNET — Serveur Data (port 5002)")
print("=" * 55)
print(" Tous les modèles sont chargés et prêts !")
print("=" * 55)


# =============================================================
#  ROUTE DE VÉRIFICATION
# =============================================================
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status" : "ok",
        "service": "YANSNET Data API",
        "port"   : 5002,
        "modeles": ["sentiment", "harcelement", "spam", "recommandation"]
    }), 200


# =============================================================
#  MODÈLE SENTIMENT
# =============================================================

@app.route("/sentiment", methods=["POST"])
def route_sentiment():
    data = request.get_json()
    if not data or "texte" not in data:
        return jsonify({"erreur": "Champ 'texte' manquant dans le body"}), 400
    texte = data["texte"]
    resultat = analyser_sentiment(texte)
    return jsonify(resultat), 200


@app.route("/sentiment/user", methods=["POST"])
def route_sentiment_user():
    data = request.get_json()
    if not data or "posts" not in data:
        return jsonify({"erreur": "Champ 'posts' manquant (liste de textes)"}), 400
    user_id = data.get("user_id", "inconnu")
    posts = data["posts"]
    if not isinstance(posts, list):
        return jsonify({"erreur": "'posts' doit être une liste de textes"}), 400
    resultat = analyser_utilisateur(posts)
    resultat["user_id"] = user_id
    return jsonify(resultat), 200


# =============================================================
#  MODÈLE HARCÈLEMENT
# =============================================================

@app.route("/harcelement", methods=["POST"])
def route_harcelement():
    data = request.get_json()
    if not data or "texte" not in data:
        return jsonify({"erreur": "Champ 'texte' manquant"}), 400
    resultat = analyser_commentaire(data["texte"])
    return jsonify(resultat), 200


@app.route("/harcelement/user", methods=["POST"])
def route_harcelement_user():
    data = request.get_json()
    if not data or "commentaires" not in data:
        return jsonify({"erreur": "Champ 'commentaires' manquant"}), 400
    harceleur_id = data.get("harceleur_id", "inconnu")
    commentaires = data["commentaires"]
    if not isinstance(commentaires, list):
        return jsonify({"erreur": "'commentaires' doit être une liste"}), 400
    resultat = analyser_harceleur(commentaires)
    resultat["harceleur_id"] = harceleur_id
    return jsonify(resultat), 200


# =============================================================
#  MODÈLE SPAM (corrigé avec conversion des types)
# =============================================================

@app.route("/spam", methods=["POST"])
def route_spam():
    """
    Détecte si le comportement d'un utilisateur est du spam.
    """
    data = request.get_json()

    if not data:
        return jsonify({"erreur": "Body JSON manquant"}), 400

    CHAMPS_SPAM = ["posts_par_min", "likes_par_min", "dm_par_min",
                   "comments_par_min", "follows_par_min", "ratio_actions_uniques"]

    user_id = data.get("user_id", "inconnu")

    comportement = {}
    for champ in CHAMPS_SPAM:
        valeur = data.get(champ)
        if valeur is not None:
            try:
                comportement[champ] = float(valeur)
            except (ValueError, TypeError):
                return jsonify({"erreur": f"Le champ '{champ}' doit être un nombre"}), 400

    resultat = detecter_spam(comportement)
    resultat["user_id"] = user_id

    # 🔧 CONVERSION DES TYPES NON SÉRIALISABLES (ex: numpy.bool_)
    def convert_to_serializable(obj):
        if isinstance(obj, (bool, int, float, str)):
            return obj
        if isinstance(obj, dict):
            return {k: convert_to_serializable(v) for k, v in obj.items()}
        if isinstance(obj, (list, tuple)):
            return [convert_to_serializable(item) for item in obj]
        # Traitement des types NumPy (bool_, int64, float64, etc.)
        if hasattr(obj, 'item'):
            return obj.item()
        # Fallback
        return str(obj)

    resultat_serialisable = convert_to_serializable(resultat)

    return jsonify(resultat_serialisable), 200


# =============================================================
#  MODÈLE RECOMMANDATION
# =============================================================

@app.route("/recommandation/<user_id>", methods=["GET"])
def route_recommandation(user_id):
    if not user_id:
        return jsonify({"erreur": "user_id manquant dans l'URL"}), 400
    resultat = obtenir_recommandations(user_id)
    if "erreur" in resultat:
        return jsonify(resultat), 503
    return jsonify(resultat), 200


# =============================================================
#  LANCEMENT DU SERVEUR
# =============================================================
if __name__ == "__main__":
    print("\n Démarrage du serveur Data sur http://localhost:5002")
    print("   Appuie sur CTRL+C pour arrêter\n")
    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    app.run(host="0.0.0.0", port=5002, debug=debug_mode)
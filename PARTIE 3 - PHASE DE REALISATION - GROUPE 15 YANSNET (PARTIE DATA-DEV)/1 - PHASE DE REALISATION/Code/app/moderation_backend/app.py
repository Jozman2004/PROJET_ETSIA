from flask import Flask, request, jsonify
from flask_cors import CORS
from transformers import pipeline
from PIL import Image
import io
import os

app = Flask(__name__)

# ============================================================
# 1. CONFIGURATION CORS (restreinte aux domaines autorisés)
# ============================================================
# En production, définissez une variable d'environnement ALLOWED_ORIGINS
# avec une liste d'origines séparées par des virgules.
# Exemple : ALLOWED_ORIGINS=https://yansnet.ucac-icam.com,https://www.yansnet.ucac-icam.com
allowed_origins = os.environ.get("ALLOWED_ORIGINS", "")
if allowed_origins:
    origins_list = [origin.strip() for origin in allowed_origins.split(",")]
else:
    # En développement, on autorise localhost et l'IP locale (10.237.64.145)
    origins_list = [
        "http://localhost:5000",
        "http://127.0.0.1:5000",
        "http://10.237.64.145:5000",  # Votre IP locale
        "https://votre-domaine.com",   # À remplacer
        "https://www.votre-domaine.com"
    ]

CORS(app, origins=origins_list)

print("🔄 Chargement des modèles IA (peut prendre quelques minutes la 1ère fois)...")

# ============================================================
# 2. CHARGEMENT DES MODÈLES
# ============================================================
text_classifier = pipeline(
    "text-classification",
    model="unitary/toxic-bert",
    return_all_scores=False
)

image_classifier = pipeline(
    "image-classification",
    model="Falconsai/nsfw_image_detection"
)

print("✅ Modèles chargés ! Serveur prêt.")

# Seuils de décision
SEUIL_TOXIQUE = 0.75   # Au‑dessus, le texte est refusé
SEUIL_NSFW = 0.70      # Au‑dessus, l'image est refusée

TOXIC_LABELS = ['toxic', 'severe_toxic', 'obscene', 'threat', 'insult', 'identity_hate']

# ============================================================
# 3. ROUTE DE MODÉRATION
# ============================================================
@app.route("/moderate", methods=["POST"])
def moderate():
    # Récupération du texte et des fichiers
    text = request.form.get("text", "").strip()
    files = request.files.getlist("images")

    # --- Modération du texte ---
    if text:
        result = text_classifier(text)[0]
        label = result['label']
        score = result['score']
        if label in TOXIC_LABELS and score > SEUIL_TOXIQUE:
            return jsonify({
                "allowed": False,
                "reason": f"Texte inapproprié ({label} : {round(score, 2)})"
            }), 400

    # --- Modération des images ---
    for img_file in files:
        img = Image.open(io.BytesIO(img_file.read()))
        predictions = image_classifier(img)
        nsfw_score = next((p['score'] for p in predictions if p['label'] == 'nsfw'), 0.0)
        if nsfw_score > SEUIL_NSFW:
            return jsonify({
                "allowed": False,
                "reason": f"Image inappropriée (score NSFW: {round(nsfw_score, 2)})"
            }), 400

    # Tout est propre
    return jsonify({"allowed": True, "message": "Contenu valide"}), 200

# ============================================================
# 4. ROUTE DE VÉRIFICATION (health check)
# ============================================================
@app.route("/", methods=["GET"])
def home():
    return jsonify({"status": "Moderation API is running"}), 200

# ============================================================
# 5. LANCEMENT (debug=False en production)
# ============================================================
if __name__ == "__main__":
    # En développement, debug=True ; en production, passez debug=False
    # et utilisez un serveur WSGI (gunicorn, uwsgi) si nécessaire.
    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    app.run(host="0.0.0.0", port=5001, debug=debug_mode)
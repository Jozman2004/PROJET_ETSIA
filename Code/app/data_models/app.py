# moderation_api.py
# Service de modération IA – YANSNET
# Port : 5001
# Rôle : Censure automatique des publications (texte, images, vidéos)
# Conforme au cahier des charges (pages 6, 8, 12, 13)

from flask import Flask, request, jsonify
from flask_cors import CORS
from transformers import pipeline
from PIL import Image, UnidentifiedImageError
import io
import os
import re
import cv2
import tempfile

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50 Mo (pour les vidéos)

CORS(app, origins=os.environ.get("YANSNET_CORS_ORIGINS", "*").split(","))

print("[INFO] Chargement des modèles IA...")

def charger_modele(sous_dossier, nom_en_ligne, task, **kwargs):
    """
    Charge un modèle depuis un dossier local (data_models/<sous_dossier>)
    si disponible, sinon le télécharge depuis Hugging Face.
    """
    local_path = os.path.join(os.path.dirname(__file__), sous_dossier)
    if os.path.exists(local_path):
        try:
            print(f"[OK] Chargement local : {sous_dossier}")
            return pipeline(task, model=local_path, **kwargs)
        except Exception as e:
            print(f"❌ Erreur chargement local {sous_dossier} : {e}")
            print(f"    Fallback vers {nom_en_ligne}...")
    else:
        print(f"📁 Dossier {sous_dossier} introuvable, téléchargement de {nom_en_ligne}...")
    return pipeline(task, model=nom_en_ligne, **kwargs)


# ── Modèle texte (toxicité) — MULTILINGUE ──
text_classifier = charger_modele(
    "toxic_text_model",
    "unitary/multilingual-toxic-xlm-roberta",
    "text-classification",
    top_k=None,
    tokenizer_kwargs={"fix_mistral_regex": True}
)

# ── Modèle image NSFW (AdamCodd/vit-base-nsfw-detector) ──
image_classifier = charger_modele(
    "nsfw_model_adam",
    "AdamCodd/vit-base-nsfw-detector",
    "image-classification"
)

# ── Modèle violence / gore / sang ──
violence_classifier = charger_modele(
    "violence_model",
    "locih/violence_classification",
    "image-classification"
)

print("[OK] Modèles chargés.")

# ── Seuils ajustés ──
SEUIL_TOXIQUE = 0.75
SEUIL_NSFW = 0.30
SEUIL_NSFW_HAUT = 0.50
SEUIL_VIOLENCE_IMAGE = 0.80          # augmenté pour réduire les faux positifs
SEUIL_VIOLENCE_VIDEO = 0.85          # augmenté pour les vidéos

# ── Liste noire enrichie ──
MOTS_INTERDITS = [
    "nègre", "bougnoul", "bicot", "sale arabe", "sale noir", "sale blanc",
    "youpin", "youp", "négro", "négresse", "blanchard", "bamboula",
    "babtou", "négrier", "esclavagiste", "colonialiste", "apartheid",
    "pd", "tarlouze", "pédé", "gouine", "tapette",
    "travelo", "enculé de bébé", "fag", "faggot",
    "viol", "meurtre", "tuer", "assassin", "génocide", "massacre",
    "pédophile", "violer", "égorger", "brûler", "lyncher", "terroriste",
    "djihadiste", "islamiste", "facho", "nazi", "hitler",
    "connard", "pute", "salope", "enculé", "nique", "fdp",
    "bâtard", "taré", "mongol", "handicapé",
    "sale", "pourri", "dégueulasse", "ordure"
]

SUGGESTIONS = {
    "nègre": "utilise 'personne noire' ou 'afrodescendant'",
    "bougnoul": "terme raciste, ne l'emploie pas",
    "pd": "terme homophobe, ne l'emploie pas",
    "tarlouze": "terme homophobe, ne l'emploie pas",
    "viol": "terme interdit, ne l'emploie pas",
    "meurtre": "terme interdit, ne l'emploie pas",
    "assassin": "terme interdit, ne l'emploie pas",
    "pédophile": "terme très grave, ne l'emploie pas",
    "connard": "personne désagréable",
    "salope": "personne méchante",
    "enculé": "personne méprisable",
    "nique": "exprime ton mécontentement autrement",
    "fdp": "évite les insultes",
    "mongol": "terme offensant, ne l'utilise pas",
}


def detecter_mots_interdits(texte):
    texte_lower = texte.lower()
    mots_trouves = []
    for mot in MOTS_INTERDITS:
        if re.search(r'\b' + re.escape(mot) + r'\b', texte_lower):
            mots_trouves.append(mot)
    if mots_trouves:
        suggestion = ", ".join(
            SUGGESTIONS.get(mot, f"remplace '{mot}' par un terme approprié")
            for mot in mots_trouves
        )
        return {
            "allowed": False,
            "reason": f"Votre message contient des mots inappropriés : {', '.join(mots_trouves)}.",
            "suggestion": f"Proposez plutôt : {suggestion}."
        }
    return None


def analyser_texte_ia(texte):
    try:
        results = text_classifier(texte[:512])[0]
        toxic_result = max(
            (r for r in results if "toxic" in r["label"].lower()
             or r["label"].lower() in ("obscene", "threat", "insult", "identity_hate", "identity_attack", "sexual_explicit")),
            key=lambda r: r["score"],
            default=None
        )
        if toxic_result is None:
            return False, None, 0.0
        return toxic_result["score"] > SEUIL_TOXIQUE, toxic_result["label"], toxic_result["score"]
    except Exception as e:
        print(f"⚠️ Erreur IA texte : {e}")
        return False, None, 0.0


def analyser_image_bytes(image_bytes):
    try:
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        # NSFW
        nsfw_predictions = image_classifier(img)
        nsfw_score = 0.0
        normal_score = 0.0
        for pred in nsfw_predictions:
            label = pred["label"].lower()
            score = pred["score"]
            if label == "normal":
                normal_score = score
            elif label == "nsfw":
                nsfw_score = score

        # Violence
        violence_predictions = violence_classifier(img)
        violence_score = 0.0
        for pred in violence_predictions:
            if pred["label"].lower() == "unsafe":
                violence_score = pred["score"]
                break

        # Pondération si image très normale
        if normal_score > 0.7:
            nsfw_score = nsfw_score * 0.6
            violence_score = violence_score * 0.6

        # --- Décision finale (ajustée) ---
        refusee = False
        motif = None

        # 1. NSFW très élevé → refus immédiat
        if nsfw_score > SEUIL_NSFW_HAUT:
            refusee = True
            motif = "nsfw (très élevé)"

        # 2. NSFW modéré + Violence élevée → refus
        elif nsfw_score > SEUIL_NSFW and violence_score > SEUIL_VIOLENCE_IMAGE:
            refusee = True
            motif = "nsfw + violence"

        # 3. Violence seule → seulement si très élevée (> 0.85)
        elif violence_score > 0.85:
            refusee = True
            motif = "violence (très élevé)"

        # 4. NSFW modéré + Violence modérée (entre 0.40 et SEUIL_VIOLENCE_IMAGE) → refus seulement si NSFW > 0.20
        elif nsfw_score > 0.20 and violence_score > 0.40:
            refusee = True
            motif = "nsfw modéré + violence modérée"

        # 5. Sinon accepté

        print(f"🔍 [DEBUG] NSFW={nsfw_score:.3f} | Violence={violence_score:.3f} | Normal={normal_score:.3f} | Refusée={refusee} | Motif={motif}")
        return {
            "nsfw": nsfw_score,
            "violence": violence_score,
            "normal": normal_score,
            "refusee": refusee,
            "motif": motif
        }
    except Exception as e:
        print(f"⚠️ Erreur analyse image : {e}")
        return {"nsfw": 0.0, "violence": 0.0, "normal": 0.0, "refusee": False, "motif": None}


def analyser_video(video_bytes):
    with tempfile.NamedTemporaryFile(delete=False, suffix='.mp4') as tmp:
        tmp.write(video_bytes)
        tmp_path = tmp.name

    try:
        cap = cv2.VideoCapture(tmp_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps <= 0:
            fps = 30

        frame_interval = max(1, int(fps * 0.5))
        frame_count = 0
        max_nsfw = 0.0
        violence_scores = []

        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_count % frame_interval == 0:
                _, img_encoded = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
                img_bytes = img_encoded.tobytes()
                scores = analyser_image_bytes(img_bytes)

                if scores["nsfw"] > max_nsfw:
                    max_nsfw = scores["nsfw"]
                violence_scores.append(scores["violence"])

                if max_nsfw > SEUIL_NSFW_HAUT:
                    break
            frame_count += 1

        cap.release()
        avg_violence = sum(violence_scores) / len(violence_scores) if violence_scores else 0.0

        refusee = False
        motif = None
        if max_nsfw > SEUIL_NSFW_HAUT:
            refusee = True
            motif = "nsfw (très élevé)"
        elif avg_violence > SEUIL_VIOLENCE_VIDEO and max_nsfw > SEUIL_NSFW:
            refusee = True
            motif = "violence moyenne + nsfw modéré"
        elif avg_violence > 0.90:
            refusee = True
            motif = "violence moyenne (très élevée)"

        print(f"📹 [VIDEO] NSFW max={max_nsfw:.3f} | Violence moyenne={avg_violence:.3f} | Refusée={refusee} | Motif={motif}")
        return {
            "nsfw": max_nsfw,
            "violence": avg_violence,
            "refusee": refusee,
            "motif": motif
        }
    except Exception as e:
        print(f"⚠️ Erreur analyse vidéo : {e}")
        return {"nsfw": 0.0, "violence": 0.0, "refusee": False, "motif": None}
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.route("/moderate", methods=["POST"])
def moderate():
    print("📥 [moderate] Requête reçue")
    text = request.form.get("text", "").strip()
    image_files = request.files.getlist("images")
    video_files = request.files.getlist("videos")

    print(f"   - Texte : {text[:100] if text else '(vide)'}")
    print(f"   - Images : {len(image_files)}")
    print(f"   - Vidéos : {len(video_files)}")

    # 1. MODÉRATION TEXTE
    if text:
        result_mots = detecter_mots_interdits(text)
        if result_mots:
            print(f"❌ [moderate] Mots interdits : {result_mots['reason']}")
            return jsonify(result_mots), 400

        est_toxique, label, score = analyser_texte_ia(text)
        print(f"🤖 [moderate] IA texte : label={label}, score={score}")
        if est_toxique:
            print(f"❌ [moderate] Texte toxique (score {score} > {SEUIL_TOXIQUE})")
            return jsonify({
                "allowed": False,
                "reason": f"Texte considéré comme toxique par l'IA ({label} : {round(score, 2)}).",
                "suggestion": "Essayez de reformuler votre message de manière plus constructive.",
                "problematic_word": text[:100]
            }), 400

    # 2. MODÉRATION IMAGES
    for img_file in image_files:
        try:
            content_type = img_file.content_type or ''
            if not content_type.startswith('image/'):
                print(f"⚠️ [moderate] Fichier ignoré (pas une image) : {img_file.filename}")
                continue

            img_bytes = img_file.read()
            if not img_bytes:
                continue

            scores = analyser_image_bytes(img_bytes)
            if scores["refusee"]:
                if "nsfw" in scores["motif"]:
                    reason = f"Image inappropriée : contenu à caractère sexuel (score NSFW: {round(scores['nsfw'], 2)})."
                    suggestion = "Utilisez une image sans nudité ni contenu sexuel explicite."
                else:
                    reason = f"Image inappropriée : violence graphique (score violence: {round(scores['violence'], 2)})."
                    suggestion = "Utilisez une image sans violence, sang ou blessures graphiques."

                print(f"❌ [moderate] Image refusée : {scores['motif']}")
                return jsonify({
                    "allowed": False,
                    "reason": reason,
                    "suggestion": suggestion
                }), 400

        except UnidentifiedImageError:
            print(f"⚠️ [moderate] Image non reconnue : {img_file.filename}")
            return jsonify({
                "allowed": False,
                "reason": "Le format de l'image n'est pas reconnu.",
                "suggestion": "Utilisez une image au format JPG, PNG ou GIF."
            }), 400
        except Exception as e:
            print(f"⚠️ [moderate] Erreur traitement image : {e}")
            continue

    # 3. MODÉRATION VIDÉOS
    for vid_file in video_files:
        try:
            print(f"📹 [moderate] Analyse vidéo : {vid_file.filename}")
            vid_bytes = vid_file.read()
            if not vid_bytes:
                continue

            resultat = analyser_video(vid_bytes)
            if resultat["refusee"]:
                if "nsfw" in resultat["motif"]:
                    reason = f"La vidéo contient des images à caractère sexuel (score max NSFW: {round(resultat['nsfw'], 2)})."
                    suggestion = "Utilisez une vidéo sans nudité ni contenu sexuel explicite."
                else:
                    reason = f"La vidéo contient des scènes potentiellement violentes (score moyen violence: {round(resultat['violence'], 2)})."
                    suggestion = "Utilisez une vidéo sans violence graphique ni sang."

                print(f"❌ [moderate] Vidéo refusée : {resultat['motif']}")
                return jsonify({
                    "allowed": False,
                    "reason": reason,
                    "suggestion": suggestion
                }), 400
        except Exception as e:
            print(f"⚠️ [moderate] Erreur analyse vidéo : {e}")
            return jsonify({
                "allowed": False,
                "reason": "La vidéo n'a pas pu être analysée (format non supporté).",
                "suggestion": "Utilisez une vidéo au format MP4."
            }), 400

    print("✅ [moderate] Contenu valide")
    return jsonify({"allowed": True, "message": "Contenu valide"}), 200


@app.route("/", methods=["GET"])
def home():
    return jsonify({"status": "Moderation API is running"}), 200


if __name__ == "__main__":
    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    app.run(host="0.0.0.0", port=5001, debug=debug_mode)
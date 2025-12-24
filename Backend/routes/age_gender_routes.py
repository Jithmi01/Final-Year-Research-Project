from flask import Blueprint, request, jsonify
from werkzeug.utils import secure_filename
import os
from services.age_gender_service import AgeGenderService
from config import Config

age_gender_bp = Blueprint("age_gender", __name__)
service = AgeGenderService()

os.makedirs(Config.UPLOAD_FOLDER, exist_ok=True)
ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png"}

def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

@age_gender_bp.route("/detect", methods=["POST"])
def detect_age_gender():
    if "image" not in request.files:
        return jsonify({"error": "No image provided"}), 400

    file = request.files["image"]
    if file.filename == "":
        return jsonify({"error": "Empty filename"}), 400
    if not allowed_file(file.filename):
        return jsonify({"error": "Invalid file type"}), 400

    strategy = request.form.get("strategy", "smart")
    if strategy not in ["simple", "smart", "conservative", "range"]:
        return jsonify({"error": "Invalid strategy"}), 400

    filename = secure_filename(file.filename)
    path = os.path.join(Config.UPLOAD_FOLDER, filename)
    file.save(path)

    try:
        result = service.detect_from_image(path, strategy=strategy)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        try: os.remove(path)
        except: pass

    if "error" in result:
        return jsonify(result), 400
    return jsonify(result), 200

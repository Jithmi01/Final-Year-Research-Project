from flask import Blueprint, request, jsonify
import os
from werkzeug.utils import secure_filename
from services.attributes_service import AttributesService
from config import Config

attributes_bp = Blueprint('attributes', __name__)
service = AttributesService()

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.',1)[1].lower() in Config.ALLOWED_EXTENSIONS

@attributes_bp.route('/detect', methods=['POST'])
def detect():
    if 'image' not in request.files:
        return jsonify({'error':'No image provided'}),400
    file = request.files['image']
    if file.filename=='':
        return jsonify({'error':'No file selected'}),400
    if not allowed_file(file.filename):
        return jsonify({'error':'Invalid file type'}),400
    os.makedirs(Config.UPLOAD_FOLDER, exist_ok=True)
    filepath = os.path.join(Config.UPLOAD_FOLDER, secure_filename(file.filename))
    file.save(filepath)
    result = service.detect_from_image(filepath)
    os.remove(filepath)
    if 'error' in result:
        return jsonify(result),400
    return jsonify(result),200

@attributes_bp.route('/health', methods=['GET'])
def health():
    return jsonify({'status':'healthy','service':'attributes_detection'}),200

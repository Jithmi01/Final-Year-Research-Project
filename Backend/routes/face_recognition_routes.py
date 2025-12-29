from flask import Blueprint, request, jsonify
from werkzeug.utils import secure_filename
import os
from services.face_recognition_service import FaceRecognitionService
from config import Config

UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

face_recognition_bp = Blueprint('face_recognition', __name__)
service = FaceRecognitionService(Config.MONGODB_URI)

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.',1)[1].lower() in ALLOWED_EXTENSIONS

@face_recognition_bp.route('/register', methods=['POST'])
def register_person():
    name = request.form.get('name')
    if not name: return jsonify({'error':'Name required'}),400
    files = [request.files[f'image{i}'] for i in range(1,6) if f'image{i}' in request.files]
    if not files: return jsonify({'error':'At least 1 image required'}),400
    paths = []
    for file in files:
        filename = secure_filename(file.filename)
        path = os.path.join(UPLOAD_FOLDER, filename)
        file.save(path)
        paths.append(path)
    result = service.register_person(name, paths)
    for p in paths: os.remove(p)
    return jsonify(result)

@face_recognition_bp.route('/recognize', methods=['POST'])
def recognize_person():
    if 'image' not in request.files: return jsonify({'error':'No image'}),400
    file = request.files['image']
    path = os.path.join(UPLOAD_FOLDER, secure_filename(file.filename))
    file.save(path)
    result = service.recognize_from_image(path)
    os.remove(path)
    return jsonify(result)

from flask import Flask, jsonify
from flask_cors import CORS
from pathlib import Path
from config import Config
import logging

# ------------------ Import Blueprints ------------------
from routes.age_gender_routes import age_gender_bp
from routes.face_recognition_routes import face_recognition_bp
from routes.attributes_routes import attributes_bp

# ------------------ Create Flask App ------------------
app = Flask(__name__)
app.config.from_object(Config)

# ------------------ Setup CORS ------------------
CORS(app, resources={r"/api/*": {"origins": "*"}})

# ------------------ Logging ------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

# ------------------ Create Required Directories ------------------
Path(Config.UPLOAD_FOLDER).mkdir(parents=True, exist_ok=True)
Path(Config.KNOWN_FACES_DIR).mkdir(parents=True, exist_ok=True)
Path(Config.EMBEDDINGS_DIR).mkdir(parents=True, exist_ok=True)

# ------------------ Register Blueprints ------------------
app.register_blueprint(age_gender_bp, url_prefix='/api/age-gender')
app.register_blueprint(face_recognition_bp, url_prefix='/api/face-recognition')
app.register_blueprint(attributes_bp, url_prefix='/api/attributes')

# ------------------ Root Endpoint ------------------
@app.route('/')
def index():
    return jsonify({
        'message': 'Blind Assistant API',
        'version': '1.0.0',
        'endpoints': {
            'age_gender': '/api/age-gender/detect',
            'face_recognition_register': '/api/face-recognition/register',
            'face_recognition_recognize': '/api/face-recognition/recognize',
            'face_recognition_people': '/api/face-recognition/people',
            'attributes': '/api/attributes/detect'
        }
    })

# ------------------ Health Check ------------------
@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'services': [
            'age_gender_detection',
            'face_recognition',
            'attributes_detection'
        ]
    })

# ------------------ Error Handlers ------------------
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

# ------------------ Run App ------------------
if __name__ == '__main__':
    logging.info("="*60)
    logging.info("BLIND ASSISTANT API SERVER")
    logging.info("="*60)
    logging.info("Starting Flask server...")
    logging.info("API will be available at: http://localhost:5000")
    logging.info("="*60)

    app.run(
        host='0.0.0.0',
        port=5000,
        debug=True,
        threaded=True
    )

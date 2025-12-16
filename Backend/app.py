from flask import Flask, jsonify
from flask_cors import CORS
from pathlib import Path
from config import Config
import logging

# ------------------ Import Blueprints ------------------
from routes.face_recognition_routes import face_recognition_bp

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
app.register_blueprint(face_recognition_bp, url_prefix='/api/face-recognition')



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

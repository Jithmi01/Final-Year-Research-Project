import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    # Flask settings
    SECRET_KEY = os.getenv('SECRET_KEY', 'your-secret-key-here')
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16MB max file size
    
    # MongoDB settings
    MONGODB_URI = os.getenv('MONGODB_URI', 'mongodb+srv://jithmi4:Jithu2001@cluster0.qas3cqk.mongodb.net/')
    MONGODB_DB_NAME = os.getenv('MONGODB_DB_NAME', 'blind_assistant')
    
    # Upload settings
    UPLOAD_FOLDER = 'uploads'
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}
    
    # Model paths
    #AGE_GENDER_MODEL_PATH = 'models/final_model_20251130-230919.h5'
    ACCESSORIES_MODEL_PATH = 'models/accessories_model.h5'
    EYEWEAR_MODEL_PATH = 'models/new_eyeware_model.h5'
    FACEWEAR_MODEL_PATH = 'models/faceware_model.h5'
    HEADWEAR_MODEL_PATH = 'models/headware_model.h5'
    NOWEAR_MODEL_PATH = 'models/noware_model.h5'
    
    # Face recognition settings
    KNOWN_FACES_DIR = 'data/known_faces'
    EMBEDDINGS_DIR = 'data/embeddings'
    FACE_RECOGNITION_THRESHOLD = 0.75
    FACE_MODEL_NAME = 'Facenet512'
    
    # Detection settings
    IMG_SIZE = 224
    DETECTION_COOLDOWN = 20  # seconds

    MONGODB_URI = "mongodb+srv://jithmi4:Jithu2001@cluster0.qas3cqk.mongodb.net/voicevision?retryWrites=true&w=majority&appName=Cluster0"
    MONGODB_DB_NAME = "face_recognition_db"
    KNOWN_FACES_DIR = "known_faces"
    EMBEDDINGS_DIR = "embeddings"
    FACE_RECOGNITION_THRESHOLD = 0.6
    DETECTION_COOLDOWN = 60  # seconds
    FOCAL_LENGTH = 600  # set this after calibrating for your camera

    
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

    IMG_SIZE = 220  # MUST MATCH TRAINING
    AGE_GENDER_MODEL_PATH = os.path.join(
        BASE_DIR, "models", "final_model_20251130-230919.h5"
    )

    UPLOAD_FOLDER = os.path.join(BASE_DIR, "uploads")
 
# FILE: config.py
# ============================================================================
# INTEGRATED CONFIGURATION
# Smart Wallet + Blind Assistant System
# ============================================================================

import os
import pytesseract
from dotenv import load_dotenv

load_dotenv()

class Config:
    # ========================================================================
    # FLASK SETTINGS
    # ========================================================================
    SECRET_KEY = os.getenv('SECRET_KEY', 'your-secret-key-here-change-in-production')
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16MB max file size
    
    # ========================================================================
    # SERVER SETTINGS
    # ========================================================================
    API_HOST = '0.0.0.0'
    API_PORT = 5000
    DEBUG = True
    CORS_ORIGINS = '*'
    
    # ========================================================================
    # DATABASE SETTINGS
    # ========================================================================
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    
    # SQLite (Smart Wallet)
    DB_NAME = os.path.join(BASE_DIR, "smart_wallet.db")
    
    # MongoDB (Face Recognition)
    MONGODB_URI = os.getenv('MONGODB_URI', 
        'mongodb+srv://jithmi4:Jithu2001@cluster0.qas3cqk.mongodb.net/voicevision?retryWrites=true&w=majority&appName=Cluster0')
    MONGODB_DB_NAME = os.getenv('MONGODB_DB_NAME', 'blind_assistant')

    # Voice Recognition - uses same MongoDB but different collection
    VOICE_DATABASE_NAME = os.getenv('DATABASE_NAME', MONGODB_DB_NAME)  # Can be same or different
    VOICE_COLLECTION_NAME = 'voice_users'  # Separate collection for voice users
    
    # ========================================================================
    # UPLOAD SETTINGS
    # ========================================================================
    UPLOAD_FOLDER = os.path.join(BASE_DIR, 'uploads')
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'bmp', 'gif', 'wav', 'mp3', 'm4a', 'ogg', 'flac'}
    ALLOWED_IMAGE_EXTENSIONS = {'png', 'jpg', 'jpeg', 'bmp', 'gif'}
    ALLOWED_AUDIO_EXTENSIONS = {'wav', 'mp3', 'm4a', 'ogg', 'flac'}
    MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB
    
    # ========================================================================
    # SMART WALLET - MODEL PATHS
    # ========================================================================
    CURRENCY_MODEL_PATH = os.path.join(BASE_DIR, "models", "Currency", "currency.pt")
    OLD_YOLO_MODEL_PATH = os.path.join(BASE_DIR, "models", "Sroie", "sroie.pt")
    NEW_YOLO_MODEL_PATH = os.path.join(BASE_DIR, "models", "Cord_dataset", "best.pt")
    
    # ========================================================================
    # BLIND ASSISTANT - MODEL PATHS
    # ========================================================================
    # Age & Gender Detection
    AGE_GENDER_MODEL_PATH = os.path.join(BASE_DIR, "models", "final_model_20251201-102857.h5")
   
    # Attributes Detection
    ACCESSORIES_MODEL_PATH = os.path.join(BASE_DIR, "models/accessories_model.h5")
    EYEWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/new_eyeware_model.h5")
    FACEWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/faceware_model.h5")
    HEADWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/headware_model.h5")
    NOWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/noware_model.h5")
    
    # Face Detection
    FACE_CASCADE_PATH = os.path.join(BASE_DIR, "haarcascade_frontalface_default.xml")

    # ========================================================================
    # VOICE RECOGNITION - MODEL PATHS & SETTINGS
    # ========================================================================
    MODEL_NAME = os.getenv('MODEL_NAME', 'speechbrain/spkrec-ecapa-voxceleb')
    MODEL_SAVE_DIR = os.getenv('MODEL_SAVE_DIR', os.path.join(BASE_DIR, 'pretrained_models'))
    
    # Voice Recognition Thresholds
    SIMILARITY_THRESHOLD = float(os.getenv('SIMILARITY_THRESHOLD', 0.65))
    MIN_AUDIO_DURATION = int(os.getenv('MIN_AUDIO_DURATION', 2))  # seconds
    MAX_AUDIO_DURATION = int(os.getenv('MAX_AUDIO_DURATION', 30))  # seconds
    
    # ========================================================================
    # TESSERACT CONFIG (Smart Wallet OCR)
    # ========================================================================
    TESSERACT_CMD = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    
    if os.path.exists(TESSERACT_CMD):
        pytesseract.pytesseract.tesseract_cmd = TESSERACT_CMD
    else:
        print("[CONFIG] ⚠️  Tesseract path not found, using system PATH")
    
    # OCR Settings
    OCR_CONFIG = {
        'lang': 'eng',
        'gpu': False,
        'max_width': 1024,
        'confidence_threshold': 40,
        'psm_modes': [3, 4, 6, 11]  # Page segmentation modes to try
    }
    
    # ========================================================================
    # SMART WALLET - BUSINESS LOGIC
    # ========================================================================
    MIN_BILL_AMOUNT = 1.0
    MAX_BILL_AMOUNT = 1000000.0
    DEFAULT_CURRENCY = 'LKR'
    CURRENCY_SYMBOL = 'Rs.'
    CURRENCY_CONFIDENCE_THRESHOLD = 0.5
    
    # ========================================================================
    # BLIND ASSISTANT - DETECTION SETTINGS
    # ========================================================================
    IMG_SIZE = 224
    ATTR_IMG_SIZE = 224
    
    # Attribute Detection Confidence Thresholds
    CONFIDENCE_THRESHOLDS = {
        'accessories': 0.60,
        'eyewear': 0.65,
        'facewear': 0.60,
        'headwear': 0.55,
        'nowear': 0.50
    }
    MIN_CONFIDENCE_GAP = 0.15
    
    # Face Recognition Settings
    KNOWN_FACES_DIR = os.path.join(BASE_DIR, 'data/known_faces')
    EMBEDDINGS_DIR = os.path.join(BASE_DIR, 'data/embeddings')
    FACE_RECOGNITION_THRESHOLD = 0.6
    DETECTION_COOLDOWN = 60  # seconds
    FOCAL_LENGTH = 600  # camera calibration for distance estimation

    # ========================================================================
    # LOGGING CONFIGURATION
    # ========================================================================
    LOG_FILE = 'app.log'
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    
    # ========================================================================
    # HELPER FUNCTIONS
    # ========================================================================
    @staticmethod
    def verify_tesseract():
        """Verify Tesseract installation"""
        try:
            version = pytesseract.get_tesseract_version()
            print(f"[CONFIG] ✓ Tesseract version: {version}")
            return True
        except Exception as e:
            print(f"[CONFIG] ✗ Tesseract not found: {e}")
            return False
    
    @staticmethod
    def allowed_file(filename):
        """Check if file extension is allowed"""
        return '.' in filename and \
               filename.rsplit('.', 1)[1].lower() in Config.ALLOWED_EXTENSIONS
    
    @staticmethod
    def allowed_image_file(filename):
        """Check if image file extension is allowed"""
        return '.' in filename and \
               filename.rsplit('.', 1)[1].lower() in Config.ALLOWED_IMAGE_EXTENSIONS
    
    
    @staticmethod
    def get_file_size(file):
        """Get file size in bytes"""
        file.seek(0, os.SEEK_END)
        size = file.tell()
        file.seek(0)
        return size
    
    @staticmethod
    def validate_image_upload(file):
        """Validate uploaded image file"""
        if not file or file.filename == '':
            return False, "No file selected"
        
        if not Config.allowed_file(file.filename):
            return False, f"Invalid file type. Allowed: {Config.ALLOWED_EXTENSIONS}"
        
        if Config.get_file_size(file) > Config.MAX_IMAGE_SIZE:
            return False, f"File too large. Max size: {Config.MAX_IMAGE_SIZE / 1024 / 1024}MB"
        
        return True, "Valid file"
    
    @staticmethod
    def create_required_directories():
        """Create all required directories"""
        directories = [
            Config.UPLOAD_FOLDER,
            Config.KNOWN_FACES_DIR,
            Config.EMBEDDINGS_DIR,
            os.path.join(Config.BASE_DIR, 'data')
        ]
        
        for directory in directories:
            os.makedirs(directory, exist_ok=True)
        
        print("[CONFIG] ✓ All required directories created")
    
    @staticmethod
    def verify_model_paths():
        """Verify that expected model files exist and log missing ones"""
        paths = {
            'CURRENCY_MODEL_PATH': Config.CURRENCY_MODEL_PATH,
            'OLD_YOLO_MODEL_PATH': Config.OLD_YOLO_MODEL_PATH,
            'NEW_YOLO_MODEL_PATH': Config.NEW_YOLO_MODEL_PATH,
            'AGE_GENDER_MODEL_PATH': Config.AGE_GENDER_MODEL_PATH,
            'ACCESSORIES_MODEL_PATH': Config.ACCESSORIES_MODEL_PATH,
            'EYEWEAR_MODEL_PATH': Config.EYEWEAR_MODEL_PATH,
            'FACEWEAR_MODEL_PATH': Config.FACEWEAR_MODEL_PATH,
            'HEADWEAR_MODEL_PATH': Config.HEADWEAR_MODEL_PATH,
            'NOWEAR_MODEL_PATH': Config.NOWEAR_MODEL_PATH
        }
        for name, path in paths.items():
            if not os.path.exists(path):
                print(f"[CONFIG] ✗ Model not found: {path}")
            else:
                print(f"[CONFIG] ✓ Model found: {path}")


    @staticmethod
    def validate():
        """
        Validate configuration settings
        
        Returns:
            tuple: (is_valid, error_messages)
        """
        errors = []
        
        # Check MongoDB URI
        if not Config.MONGODB_URI:
            errors.append("MONGODB_URI is not set in .env file")
        
        # Check voice threshold range
        if not (0.0 <= Config.SIMILARITY_THRESHOLD <= 1.0):
            errors.append(f"SIMILARITY_THRESHOLD must be between 0.0 and 1.0, got {Config.SIMILARITY_THRESHOLD}")
        
        # Check duration values
        if Config.MIN_AUDIO_DURATION <= 0:
            errors.append(f"MIN_AUDIO_DURATION must be positive, got {Config.MIN_AUDIO_DURATION}")
        
        if Config.MAX_AUDIO_DURATION <= Config.MIN_AUDIO_DURATION:
            errors.append(f"MAX_AUDIO_DURATION must be greater than MIN_AUDIO_DURATION")
        
        return (len(errors) == 0, errors)
    
    @staticmethod
    def init_app(app):
        """
        Initialize Flask app with configuration
        
        Args:
            app: Flask application instance
        """
        # Set Flask config
        app.config.from_object(Config)
        
        # Create required directories
        Config.create_required_directories()

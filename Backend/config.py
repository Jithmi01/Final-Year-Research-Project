# FILE: config.py
# ============================================================================
# INTEGRATED CONFIGURATION - WITH FIREBASE + VOICE RECOGNITION
# Smart Wallet + Blind Assistant System + Voice Recognition
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
    API_PORT = int(os.getenv('FLASK_PORT', 5000))
    DEBUG = os.getenv('FLASK_DEBUG', 'True').lower() in ('true', '1', 'yes')
    CORS_ORIGINS = '*'
    
    # ========================================================================
    # DATABASE SETTINGS
    # ========================================================================
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    
    # ⭐ DATABASE TYPE: Choose 'sqlite' or 'firebase'
    DATABASE_TYPE = os.getenv('DATABASE_TYPE', 'firebase')
    
    # SQLite (Old - Keep for backup)
    DB_NAME = os.path.join(BASE_DIR, "smart_wallet.db")
    
    # ⭐ Firebase Settings
    FIREBASE_CREDENTIALS = os.path.join(BASE_DIR, "firebase-credentials.json")
    
    # ⭐ MongoDB Settings (Voice Recognition + Face Recognition)
    MONGODB_URI = os.getenv('MONGODB_URI', 
        'mongodb+srv://jithmi4:Jithu2001@cluster0.qas3cqk.mongodb.net/voicevision?retryWrites=true&w=majority&appName=Cluster0')
    MONGODB_DB_NAME = os.getenv('MONGODB_DB_NAME', 'blind_assistant')
    
    # ⭐ Voice Recognition MongoDB Collection
    VOICE_COLLECTION_NAME = os.getenv('VOICE_COLLECTION_NAME', 'voice_users')
    
    # ========================================================================
    # FIREBASE COLLECTIONS
    # ========================================================================
    TRANSACTIONS_COLLECTION = 'transactions'
    BILLS_COLLECTION = 'bills'
    WEEKLY_SUMMARIES_COLLECTION = 'weekly_summaries'
    SAVINGS_GOALS_COLLECTION = 'savings_goals'
    USERS_COLLECTION = 'users'
    
    # ========================================================================
    # UPLOAD SETTINGS
    # ========================================================================
    UPLOAD_FOLDER = os.path.join(BASE_DIR, 'uploads')
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'bmp', 'gif'}
    MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB
    
    # ⭐ VOICE RECOGNITION - ALLOWED AUDIO FORMATS
    ALLOWED_AUDIO_EXTENSIONS = {'wav', 'mp3', 'm4a', 'ogg', 'flac'}
    
    # ========================================================================
    # SMART WALLET - MODEL PATHS
    # ========================================================================
    CURRENCY_MODEL_PATH = r'E:/research/currency/smart-wallet-backend/models/currency_model/best.pt'
    OLD_YOLO_MODEL_PATH = os.path.join(BASE_DIR, "models", "Sroie", "sroie.pt")
    NEW_YOLO_MODEL_PATH = r'E:/research/New folder/smart-wallet-backend/models/Cord/best (9).pt'

    # ========================================================================
    # BLIND ASSISTANT - MODEL PATHS
    # ========================================================================
    # Age & Gender Detection
    AGE_GENDER_MODEL_PATH = os.path.join(BASE_DIR, "models", "final_model_20251201-102857.h5")
       
    ACCESSORIES_MODEL_PATH = os.path.join(BASE_DIR, "models/accessories_model.h5")
    EYEWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/new_eyeware_model.h5")
    FACEWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/faceware_model.h5")
    HEADWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/headware_model.h5")
    NOWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/noware_model.h5")
    
    FACE_CASCADE_PATH = os.path.join(BASE_DIR, "haarcascade_frontalface_default.xml")
    
    # ========================================================================
    # ⭐ VOICE RECOGNITION CONFIGURATION
    # ========================================================================
    # Similarity threshold for speaker identification (0.0 - 1.0)
    SIMILARITY_THRESHOLD = float(os.getenv('SIMILARITY_THRESHOLD', 0.65))
    
    # Audio validation
    MIN_AUDIO_DURATION = int(os.getenv('MIN_AUDIO_DURATION', 2))  # seconds
    MAX_AUDIO_DURATION = int(os.getenv('MAX_AUDIO_DURATION', 30))  # seconds
    
    # Model configuration
    VOICE_MODEL_NAME = os.getenv('MODEL_NAME', 'speechbrain/spkrec-ecapa-voxceleb')
    VOICE_MODEL_SAVE_DIR = os.getenv('MODEL_SAVE_DIR', os.path.join(BASE_DIR, 'pretrained_models'))
    
    WHISPER_MODEL_SIZE = os.getenv('WHISPER_MODEL_SIZE', 'base')
    # ========================================================================
    # TESSERACT CONFIG (Smart Wallet OCR)
    # ========================================================================
    TESSERACT_CMD = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    
    if os.path.exists(TESSERACT_CMD):
        pytesseract.pytesseract.tesseract_cmd = TESSERACT_CMD
    
    OCR_CONFIG = {
        'lang': 'eng',
        'gpu': False,
        'max_width': 1024,
        'confidence_threshold': 40,
        'psm_modes': [3, 4, 6, 11]
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
    
    CONFIDENCE_THRESHOLDS = {
        'accessories': 0.60,
        'eyewear': 0.65,
        'facewear': 0.60,
        'headwear': 0.55,
        'nowear': 0.50
    }
    MIN_CONFIDENCE_GAP = 0.15
    
    KNOWN_FACES_DIR = os.path.join(BASE_DIR, 'data/known_faces')
    EMBEDDINGS_DIR = os.path.join(BASE_DIR, 'data/embeddings')
    FACE_RECOGNITION_THRESHOLD = 0.6
    DETECTION_COOLDOWN = 60
    FOCAL_LENGTH = 600
    
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
        """Check if file extension is allowed (images)"""
        return '.' in filename and \
               filename.rsplit('.', 1)[1].lower() in Config.ALLOWED_EXTENSIONS
    
    @staticmethod
    def allowed_audio_file(filename):
        """Check if audio file extension is allowed"""
        return '.' in filename and \
               filename.rsplit('.', 1)[1].lower() in Config.ALLOWED_AUDIO_EXTENSIONS
    
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
    def validate_audio_upload(file):
        """Validate uploaded audio file"""
        if not file or file.filename == '':
            return False, "No audio file selected"
        
        if not Config.allowed_audio_file(file.filename):
            return False, f"Invalid audio type. Allowed: {Config.ALLOWED_AUDIO_EXTENSIONS}"
        
        if Config.get_file_size(file) > Config.MAX_CONTENT_LENGTH:
            return False, f"Audio file too large. Max size: {Config.MAX_CONTENT_LENGTH / 1024 / 1024}MB"
        
        return True, "Valid audio file"
    
    @staticmethod
    def create_required_directories():
        """Create all required directories"""
        directories = [
            Config.UPLOAD_FOLDER,
            Config.KNOWN_FACES_DIR,
            Config.EMBEDDINGS_DIR,
            Config.VOICE_MODEL_SAVE_DIR,  # ⭐ Voice model directory
            os.path.join(Config.BASE_DIR, 'data')
        ]
        
        for directory in directories:
            os.makedirs(directory, exist_ok=True)
        
        print("[CONFIG] ✓ All required directories created")
    
    @staticmethod
    def validate_voice_config():
        """Validate voice recognition configuration"""
        errors = []
        
        if not Config.MONGODB_URI:
            errors.append("MONGODB_URI is not set in .env file")
        
        if not (0.0 <= Config.SIMILARITY_THRESHOLD <= 1.0):
            errors.append(f"SIMILARITY_THRESHOLD must be between 0.0 and 1.0, got {Config.SIMILARITY_THRESHOLD}")
        
        if Config.MIN_AUDIO_DURATION <= 0:
            errors.append(f"MIN_AUDIO_DURATION must be positive, got {Config.MIN_AUDIO_DURATION}")
        
        if Config.MAX_AUDIO_DURATION <= Config.MIN_AUDIO_DURATION:
            errors.append(f"MAX_AUDIO_DURATION must be greater than MIN_AUDIO_DURATION")
        
        return len(errors) == 0, errors
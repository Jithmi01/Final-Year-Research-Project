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
    
    # ========================================================================
    # UPLOAD SETTINGS
    # ========================================================================
    UPLOAD_FOLDER = os.path.join(BASE_DIR, 'uploads')
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'bmp', 'gif'}
    MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB
    
    # ========================================================================
    # SMART WALLET - MODEL PATHS
    # ========================================================================
    CURRENCY_MODEL_PATH = r'"E:/research/New folder/smart-wallet-backend/models/currency_model/New folder/best (5).pt"'
    OLD_YOLO_MODEL_PATH = r'E:/research/New folder/smart-wallet-backend/models/new_model/sroie/best (6).pt'
    NEW_YOLO_MODEL_PATH = r'E:/currency/python_backend/models/new_model/best.pt'
    
    # ========================================================================
    # BLIND ASSISTANT - MODEL PATHS
    # ========================================================================
    # Age & Gender Detection
    AGE_GENDER_MODEL_PATH = r'E:\research\New folder\smart-wallet-backend\models\final_model_20251201-102857.h5'
   
    # Attributes Detection
    ACCESSORIES_MODEL_PATH = os.path.join(BASE_DIR, "models/accessories_model.h5")
    EYEWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/new_eyeware_model.h5")
    FACEWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/faceware_model.h5")
    HEADWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/headware_model.h5")
    NOWEAR_MODEL_PATH = os.path.join(BASE_DIR, "models/noware_model.h5")
    
    # Face Detection
    FACE_CASCADE_PATH = os.path.join(BASE_DIR, "haarcascade_frontalface_default.xml")
    
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
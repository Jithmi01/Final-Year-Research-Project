# FILE: app/config/settings.py
# ============================================================================

"""
Configuration Settings
All application configuration in one place
"""

import pytesseract
import os

# ============================================================================
# PATHS
# ============================================================================

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))

# Database
DB_NAME = os.path.join(BASE_DIR, "smart_wallet.db")

# Model paths
CURRENCY_MODEL_PATH = r'E:/research/currency/smart-wallet-backend/models/currency_model/best.pt'
OLD_YOLO_MODEL_PATH = r'F:/Kavindu/SROIE2019/runs/sroie_yolo_m_high_accuracy_fast/weights/best.pt'
NEW_YOLO_MODEL_PATH = r'E:/currency/python_backend/models/new_model/best.pt'

# ============================================================================
# TESSERACT CONFIG
# ============================================================================

TESSERACT_CMD = r"C:\Program Files\Tesseract-OCR\tesseract.exe"

if os.path.exists(TESSERACT_CMD):
    pytesseract.pytesseract.tesseract_cmd = TESSERACT_CMD
else:
    print("[CONFIG] ⚠️  Tesseract path not found, using system PATH")

# ============================================================================
# OCR SETTINGS
# ============================================================================

OCR_CONFIG = {
    'lang': 'eng',
    'gpu': False,
    'max_width': 1024,
    'confidence_threshold': 40,
    'psm_modes': [3, 4, 6, 11]  # Page segmentation modes to try
}

# ============================================================================
# API SETTINGS
# ============================================================================

API_HOST = '0.0.0.0'
API_PORT = 5000
DEBUG = True

# CORS settings
CORS_ORIGINS = '*'

# ============================================================================
# VALIDATION
# ============================================================================

MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'bmp', 'gif'}

# ============================================================================
# BUSINESS LOGIC SETTINGS
# ============================================================================

# Currency detection
CURRENCY_CONFIDENCE_THRESHOLD = 0.5

# Bill processing
MIN_BILL_AMOUNT = 1.0
MAX_BILL_AMOUNT = 1000000.0

# Wallet
DEFAULT_CURRENCY = 'LKR'
CURRENCY_SYMBOL = 'Rs.'

# ============================================================================
# HELPERS
# ============================================================================

def verify_tesseract():
    """Verify Tesseract installation"""
    try:
        version = pytesseract.get_tesseract_version()
        print(f"[CONFIG] ✓ Tesseract version: {version}")
        return True
    except Exception as e:
        print(f"[CONFIG] ✗ Tesseract not found: {e}")
        print("[CONFIG] Install from: https://github.com/UB-Mannheim/tesseract/wiki")
        return False

def allowed_file(filename):
    """Check if file extension is allowed"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_file_size(file):
    """Get file size in bytes"""
    file.seek(0, os.SEEK_END)
    size = file.tell()
    file.seek(0)
    return size

def validate_image_upload(file):
    """Validate uploaded image file"""
    if not file or file.filename == '':
        return False, "No file selected"
    
    if not allowed_file(file.filename):
        return False, f"Invalid file type. Allowed: {ALLOWED_EXTENSIONS}"
    
    if get_file_size(file) > MAX_IMAGE_SIZE:
        return False, f"File too large. Max size: {MAX_IMAGE_SIZE / 1024 / 1024}MB"
    
    return True, "Valid file"

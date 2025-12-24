# FILE: app/config/settings.py
# ============================================================================
# SMART WALLET SETTINGS - Backward Compatibility Layer
# ============================================================================

"""
Configuration Settings for Smart Wallet
Now imports from root config.py for unified configuration
Maintains backward compatibility with existing Smart Wallet code
"""

import sys
import os

# Add parent directory to path to import from root
parent_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

# Import the unified Config class
from config import Config

# ============================================================================
# RE-EXPORT ALL SETTINGS FOR BACKWARD COMPATIBILITY
# ============================================================================

# Paths
BASE_DIR = Config.BASE_DIR
DB_NAME = Config.DB_NAME

# Model paths
CURRENCY_MODEL_PATH = Config.CURRENCY_MODEL_PATH
OLD_YOLO_MODEL_PATH = Config.OLD_YOLO_MODEL_PATH
NEW_YOLO_MODEL_PATH = Config.NEW_YOLO_MODEL_PATH

# Tesseract
TESSERACT_CMD = Config.TESSERACT_CMD

# OCR Settings
OCR_CONFIG = Config.OCR_CONFIG

# API Settings
API_HOST = Config.API_HOST
API_PORT = Config.API_PORT
DEBUG = Config.DEBUG
CORS_ORIGINS = Config.CORS_ORIGINS

# Validation
MAX_IMAGE_SIZE = Config.MAX_IMAGE_SIZE
ALLOWED_EXTENSIONS = Config.ALLOWED_EXTENSIONS

# Business Logic Settings
MIN_BILL_AMOUNT = Config.MIN_BILL_AMOUNT
MAX_BILL_AMOUNT = Config.MAX_BILL_AMOUNT
DEFAULT_CURRENCY = Config.DEFAULT_CURRENCY
CURRENCY_SYMBOL = Config.CURRENCY_SYMBOL
CURRENCY_CONFIDENCE_THRESHOLD = Config.CURRENCY_CONFIDENCE_THRESHOLD

# ============================================================================
# RE-EXPORT HELPER FUNCTIONS
# ============================================================================

verify_tesseract = Config.verify_tesseract
allowed_file = Config.allowed_file
get_file_size = Config.get_file_size
validate_image_upload = Config.validate_image_upload
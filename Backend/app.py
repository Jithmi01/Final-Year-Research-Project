# FILE: app.py
# ============================================================================
# INTEGRATED MAIN APPLICATION - WITH FIREBASE SUPPORT + ANALYTICS
# Smart Wallet + Blind Assistant System + Expense Dashboard
# ============================================================================

from flask import Flask, jsonify
from flask_cors import CORS
from pathlib import Path
import logging
import os

# Configuration
from config import Config

# Database initialization
if Config.DATABASE_TYPE == 'firebase':
    from app.models.firebase_database import init_firebase, ensure_firebase_ready
else:
    from app.models.database import init_all_databases, ensure_database_ready

# ============================================================================
# IMPORT ALL BLUEPRINTS
# ============================================================================

# Smart Wallet Routes
from app.routes.bill_routes import bill_bp
from app.routes.wallet_routes import wallet_bp
from app.routes.currency_routes import currency_bp
from app.routes.legacy_routes import legacy_bp

# ⭐ NEW: Analytics Routes for Expense Dashboard
from app.routes.analytics_routes import analytics_bp
from app.routes.document_routes import document_bp



# Blind Assistant Routes (Optional)
age_gender_available = False
face_recognition_available = False
attributes_available = False

try:
    if os.path.exists(Config.AGE_GENDER_MODEL_PATH):
        from routes.age_gender_routes import age_gender_bp
        age_gender_available = True
        print("✓ Age & Gender Detection: Available")
    else:
        print(f"⚠ Age & Gender model not found")
except Exception as e:
    print(f"⚠ Age & Gender Detection: Disabled ({e})")

try:
    from routes.face_recognition_routes import face_recognition_bp
    face_recognition_available = True
    print("✓ Face Recognition: Available")
except Exception as e:
    print(f"⚠ Face Recognition: Disabled ({e})")

try:
    if all([
        os.path.exists(Config.ACCESSORIES_MODEL_PATH),
        os.path.exists(Config.EYEWEAR_MODEL_PATH),
        os.path.exists(Config.FACEWEAR_MODEL_PATH),
        os.path.exists(Config.HEADWEAR_MODEL_PATH),
        os.path.exists(Config.NOWEAR_MODEL_PATH)
    ]):
        from routes.attributes_routes import attributes_bp
        attributes_available = True
        print("✓ Attributes Detection: Available")
    else:
        print("⚠ Attributes models not found")
except Exception as e:
    print(f"⚠ Attributes Detection: Disabled ({e})")

# ============================================================================
# LOGGING SETUP
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ============================================================================
# CREATE FLASK APP
# ============================================================================

def create_app():
    """Create and configure the integrated Flask application"""
    
    app = Flask(__name__)
    app.config.from_object(Config)
    
    # Enable CORS for all routes
    CORS(app, resources={r"/*": {"origins": "*"}})
    
    # ========================================================================
    # INITIALIZE SYSTEMS
    # ========================================================================
    
    logger.info("="*80)
    logger.info("  🚀 INTEGRATED SYSTEM - STARTING UP")
    logger.info("="*80)
    
    # Create required directories
    Config.create_required_directories()
    
    # Initialize Database
    if Config.DATABASE_TYPE == 'firebase':
        logger.info("Initializing Firebase Firestore Database...")
        if init_firebase():
            ensure_firebase_ready()
            logger.info("✓ Firebase Firestore Database ready")
        else:
            logger.error("✗ Firebase initialization failed!")
            logger.error("  Make sure firebase-credentials.json is in the project root")
    else:
        logger.info("Initializing SQLite Database...")
        init_all_databases()
        ensure_database_ready()
        logger.info("✓ SQLite Database ready")
    
    # Verify Tesseract for OCR
    tesseract_ok = Config.verify_tesseract()
    
    logger.info("="*80)
    
    # ========================================================================
    # REGISTER BLUEPRINTS
    # ========================================================================
    
    # Smart Wallet Blueprints (Always available)
    app.register_blueprint(bill_bp)
    app.register_blueprint(wallet_bp)
    app.register_blueprint(currency_bp)
    app.register_blueprint(legacy_bp)
    logger.info("✓ Smart Wallet blueprints registered")
    app.register_blueprint(document_bp)
    logger.info("✓ Document Reader blueprint registered")

    # ⭐ NEW: Analytics Blueprint for Expense Dashboard
    app.register_blueprint(analytics_bp)
    logger.info("✓ Analytics/Dashboard blueprint registered")
    
    # Blind Assistant Blueprints (Optional)
    if age_gender_available:
        app.register_blueprint(age_gender_bp, url_prefix='/api/age-gender')
        logger.info("✓ Age & Gender blueprint registered")
    
    if face_recognition_available:
        app.register_blueprint(face_recognition_bp, url_prefix='/api/face-recognition')
        logger.info("✓ Face Recognition blueprint registered")
    
    if attributes_available:
        app.register_blueprint(attributes_bp, url_prefix='/api/attributes')
        logger.info("✓ Attributes blueprint registered")
    
    # ========================================================================
    # ROOT ENDPOINTS
    # ========================================================================
    
    @app.route('/', methods=['GET'])
    def root():
        """Root endpoint - API overview"""
        blind_assistant_status = {
            'age_gender': 'available' if age_gender_available else 'disabled',
            'face_recognition': 'available' if face_recognition_available else 'disabled',
            'attributes': 'available' if attributes_available else 'disabled'
        }
        
        return jsonify({
            'message': 'Integrated Smart Wallet + Blind Assistant API',
            'version': '2.1.0',  # Updated version
            'status': 'running',
            'database': Config.DATABASE_TYPE.upper(),
            'systems': {
                'smart_wallet': {
                    'status': 'active',
                    'database': Config.DATABASE_TYPE,
                    'description': 'Bill scanning, wallet management, currency detection, expense analytics',
                    'endpoints': {
                        'bills': '/api/bill/*',
                        'wallet': '/api/wallet/*',
                        'currency': '/api/currency/*',
                        'analytics': '/api/analytics/*',  # ⭐ NEW
                        'legacy': '/scan_bill_display_only, /get_wallet_balance, /get_expense_dashboard, etc.'
                    }
                },
                'blind_assistant': {
                    'status': blind_assistant_status,
                    'description': 'Age/gender detection, face recognition, attribute detection',
                    'endpoints': {
                        'age_gender': '/api/age-gender/detect' if age_gender_available else 'disabled',
                        'face_recognition_register': '/api/face-recognition/register' if face_recognition_available else 'disabled',
                        'face_recognition_recognize': '/api/face-recognition/recognize' if face_recognition_available else 'disabled',
                        'attributes': '/api/attributes/detect' if attributes_available else 'disabled'
                    }
                }
            },
            'documentation': {
                'health_check': '/health',
                'smart_wallet_health': '/health/wallet',
                'blind_assistant_health': '/health/assistant'
            }
        }), 200
    
    @app.route('/health', methods=['GET'])
    def health_check():
        """Complete health check for all systems"""
        blind_assistant_services = []
        if age_gender_available:
            blind_assistant_services.append('age_gender')
        if face_recognition_available:
            blind_assistant_services.append('face_recognition')
        if attributes_available:
            blind_assistant_services.append('attributes')
        
        db_status = 'connected' if Config.DATABASE_TYPE == 'firebase' else 'connected'
        
        return jsonify({
            'status': 'healthy',
            'database': Config.DATABASE_TYPE,
            'systems': {
                'smart_wallet': {
                    'database': db_status,
                    'database_type': Config.DATABASE_TYPE,
                    'tesseract': tesseract_ok,
                    'services': [
                        'bill_scanner', 
                        'wallet', 
                        'currency_detector',
                        'expense_analytics'  # ⭐ NEW
                    ]
                },
                'blind_assistant': {
                    'services': blind_assistant_services if blind_assistant_services else ['none - models not found'],
                    'mongodb': 'connected' if face_recognition_available else 'not required'
                }
            }
        }), 200
    
    @app.route('/health/wallet', methods=['GET'])
    def health_wallet():
        """Smart Wallet specific health check"""
        return jsonify({
            'system': 'smart_wallet',
            'status': 'healthy',
            'database': Config.DATABASE_TYPE,
            'tesseract': tesseract_ok,
            'services': {
                'bill_scanner': 'active',
                'wallet_service': 'active',
                'currency_detector': 'active',
                'ocr_service': 'active',
                'expense_analytics': 'active'  # ⭐ NEW
            }
        }), 200
    
    @app.route('/health/assistant', methods=['GET'])
    def health_assistant():
        """Blind Assistant specific health check"""
        services_status = {
            'age_gender_detection': 'active' if age_gender_available else 'disabled',
            'face_recognition': 'active' if face_recognition_available else 'disabled',
            'attributes_detection': 'active' if attributes_available else 'disabled'
        }
        
        return jsonify({
            'system': 'blind_assistant',
            'status': 'partial' if any([age_gender_available, face_recognition_available, attributes_available]) else 'disabled',
            'mongodb': 'connected' if face_recognition_available else 'not required',
            'services': services_status
        }), 200
    
    # ========================================================================
    # ERROR HANDLERS
    # ========================================================================
    
    @app.errorhandler(404)
    def not_found(error):
        return jsonify({
            'error': 'Endpoint not found',
            'message': 'The requested URL was not found on the server',
            'available_systems': {
                'smart_wallet': '/api/bill, /api/wallet, /api/currency, /api/analytics',
                'blind_assistant': '/api/age-gender, /api/face-recognition, /api/attributes (check /health for availability)'
            }
        }), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        logger.error(f"Internal Server Error: {error}")
        return jsonify({
            'error': 'Internal server error',
            'message': 'An unexpected error occurred. Please check server logs.'
        }), 500
    
    @app.errorhandler(400)
    def bad_request(error):
        return jsonify({
            'error': 'Bad request',
            'message': 'The request could not be understood by the server'
        }), 400
    
    @app.errorhandler(413)
    def request_entity_too_large(error):
        return jsonify({
            'error': 'File too large',
            'message': f'Maximum file size is {Config.MAX_CONTENT_LENGTH / (1024*1024)}MB'
        }), 413
    
    return app

# ============================================================================
# CREATE APP INSTANCE
# ============================================================================

app = create_app()

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

if __name__ == "__main__":
    print("\n" + "="*80)
    print("  🚀 INTEGRATED SYSTEM - SMART WALLET + BLIND ASSISTANT")
    print("="*80)
    print(f"\n  💾 DATABASE: {Config.DATABASE_TYPE.upper()}")
    print("\n  📦 SMART WALLET FEATURES:")
    print("     ✓ Bill Scanner (YOLO + OCR)")
    print("     ✓ Wallet Management")
    print("     ✓ Currency Detection")
    print("     ✓ Transaction Tracking")
    print("     ✓ Category Classification")
    print("     ✓ Expense Analytics Dashboard")  # ⭐ NEW
    print("     ✓ AI-Powered Spending Alerts")   # ⭐ NEW
    print("\n  👁️  BLIND ASSISTANT FEATURES:")
    if age_gender_available:
        print("     ✓ Age & Gender Detection")
    else:
        print("     ✗ Age & Gender Detection (model not found)")
    
    if face_recognition_available:
        print("     ✓ Face Recognition")
    else:
        print("     ✗ Face Recognition (disabled)")
    
    if attributes_available:
        print("     ✓ Attribute Detection (glasses, masks, etc.)")
    else:
        print("     ✗ Attribute Detection (models not found)")
    
    print("\n  🌐 Server Info:")
    print(f"     URL: http://{Config.API_HOST}:{Config.API_PORT}")
    print(f"     Debug Mode: {Config.DEBUG}")
    print("\n  📚 API Documentation:")
    print("     Root: /")
    print("     Health: /health")
    print("     Smart Wallet: /api/bill, /api/wallet, /api/currency")
    print("     Analytics: /api/analytics/dashboard, /api/analytics/report")  # ⭐ NEW
    print("     Legacy: /get_expense_dashboard, /generate_expense_report")    # ⭐ NEW
    if age_gender_available or face_recognition_available or attributes_available:
        print("     Blind Assistant: /api/age-gender, /api/face-recognition, /api/attributes")
    print("="*80 + "\n")
    
    app.run(
        host=Config.API_HOST,
        port=Config.API_PORT,
        debug=Config.DEBUG,
        threaded=True
    )
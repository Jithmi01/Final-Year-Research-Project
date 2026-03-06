# FILE: app.py
# ============================================================================
# INTEGRATED MAIN APPLICATION - WITH FIREBASE + VOICE RECOGNITION
# Smart Wallet + Blind Assistant System + Voice Recognition + Expense Dashboard
# ============================================================================

from flask import Flask, jsonify
from flask_cors import CORS
from pathlib import Path
import logging
import os
import sys

# Configuration
from config import Config

# Database initialization
if Config.DATABASE_TYPE == 'firebase':
    from app.models.firebase_database import init_firebase, ensure_firebase_ready
else:
    from app.models.database import init_all_databases, ensure_database_ready

from pymongo import MongoClient

# ============================================================================
# IMPORT ALL BLUEPRINTS
# ============================================================================

# Smart Wallet Routes
from app.routes.bill_routes import bill_bp
from app.routes.wallet_routes import wallet_bp
from app.routes.currency_routes import currency_bp
from app.routes.legacy_routes import legacy_bp
from app.routes.analytics_routes import analytics_bp
from app.routes.document_routes import document_bp

# Face Detection - Individual
from routes.age_gender_routes import age_gender_bp
from routes.face_recognition_routes import face_recognition_bp
from routes.attributes_routes import attributes_bp

# Face Detection - INTEGRATED
from routes.integrated_face_routes import integrated_face_bp, init_integrated_service

# ⭐ NEW: Voice Recognition
from routes.voice_routes import init_voice_routes
from services.voice_service import VoiceRecognitionService
from utils.audio_processor import AudioProcessor

# Blind Assistant Routes availability check
age_gender_available = False
face_recognition_available = False
attributes_available = False

try:
    if os.path.exists(Config.AGE_GENDER_MODEL_PATH):
        age_gender_available = True
        print("✓ Age & Gender Detection: Available")
except Exception as e:
    print(f"⚠ Age & Gender Detection: Disabled ({e})")

try:
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
        attributes_available = True
        print("✓ Attributes Detection: Available")
except Exception as e:
    print(f"⚠ Attributes Detection: Disabled ({e})")

# ============================================================================
# LOGGING SETUP
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('app.log', encoding='utf-8')
    ]
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
    
    # Initialize Database (Firebase/SQLite)
    if Config.DATABASE_TYPE == 'firebase':
        logger.info("Initializing Firebase Firestore Database...")
        if init_firebase():
            ensure_firebase_ready()
            logger.info("✓ Firebase Firestore Database ready")
        else:
            logger.error("✗ Firebase initialization failed!")
    else:
        logger.info("Initializing SQLite Database...")
        init_all_databases()
        ensure_database_ready()
        logger.info("✓ SQLite Database ready")
    
    # Verify Tesseract for OCR
    tesseract_ok = Config.verify_tesseract()
    
    # ========================================================================
    # INITIALIZE MONGODB (Face + Voice Recognition)
    # ========================================================================
    mongodb_ready = False
    try:
        logger.info("Initializing MongoDB Connection...")
        mongo_client = MongoClient(Config.MONGODB_URI, serverSelectionTimeoutMS=5000)
        mongo_client.admin.command('ping')
        db = mongo_client[Config.MONGODB_DB_NAME]
        
        # Check collections
        face_users_count = db.get_collection('users').count_documents({})
        voice_users_count = db.get_collection(Config.VOICE_COLLECTION_NAME).count_documents({})
        
        logger.info(f"✓ MongoDB connected | Database: {Config.MONGODB_DB_NAME}")
        logger.info(f"  - Face Recognition Users: {face_users_count}")
        logger.info(f"  - Voice Recognition Users: {voice_users_count}")
        
        mongodb_ready = True
        mongo_client.close()
        
    except Exception as e:
        logger.error(f"✗ MongoDB connection failed: {e}")
        mongodb_ready = False
    
    # ========================================================================
    # ⭐ INITIALIZE VOICE RECOGNITION SERVICES
    # ========================================================================
    voice_recognition_ready = False
    audio_processor = None
    voice_service = None
    
    try:
        logger.info("="*60)
        logger.info("🎤 Initializing Voice Recognition Services")
        logger.info("="*60)
        
        # Validate voice config
        is_valid, errors = Config.validate_voice_config()
        if not is_valid:
            logger.error("Voice configuration errors:")
            for error in errors:
                logger.error(f"  - {error}")
            raise Exception("Voice configuration validation failed")
        
        # Initialize Audio Processor
        logger.info("🎵 Initializing audio processor...")
        audio_processor = AudioProcessor(target_sr=16000)
        logger.info("✅ Audio processor ready")
        
        # Initialize Voice Recognition Service
        logger.info("🧠 Loading voice recognition model...")
        logger.info("⏳ First run: Downloading model (~500MB, 2-5 minutes)")
        
        voice_service = VoiceRecognitionService(
            model_name=Config.VOICE_MODEL_NAME,
            model_save_dir=Config.VOICE_MODEL_SAVE_DIR
        )
        
        logger.info("✅ Voice recognition service initialized")
        voice_recognition_ready = True
        logger.info("="*60)
        
    except Exception as e:
        logger.error(f"✗ Voice recognition initialization failed: {e}")
        logger.error("  Voice recognition features will be disabled")
        import traceback
        logger.error(traceback.format_exc())
        voice_recognition_ready = False
    
    # ========================================================================
    # INITIALIZE INTEGRATED FACE DETECTION
    # ========================================================================
    integrated_face_ready = False
    try:
        logger.info("Initializing Integrated Face Detection...")
        init_integrated_service(Config.MONGODB_URI)
        integrated_face_ready = True
        logger.info("  ✓ Integrated Face Detection ready")
    except Exception as e:
        logger.error(f"✗ Integrated Face Detection failed: {e}")
        integrated_face_ready = False
    
    logger.info("="*80)
    
    # ========================================================================
    # REGISTER BLUEPRINTS
    # ========================================================================
    
    # Smart Wallet Blueprints (Always available)
    app.register_blueprint(bill_bp)
    app.register_blueprint(wallet_bp)
    app.register_blueprint(currency_bp)
    app.register_blueprint(legacy_bp)
    app.register_blueprint(analytics_bp)
    app.register_blueprint(document_bp)
    logger.info("✓ Smart Wallet blueprints registered")
    
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
    
    # Integrated Face Detection
    app.register_blueprint(integrated_face_bp, url_prefix='/api/integrated-face')
    if integrated_face_ready:
        logger.info("  ✓ Integrated Face Detection (LIVE) - ACTIVE")
    
    # ⭐ Voice Recognition Blueprints
    if voice_recognition_ready and mongodb_ready:
        try:
            voice_bp = init_voice_routes(
                audio_processor=audio_processor,
                voice_service=voice_service,
                mongo_uri=Config.MONGODB_URI,
                db_name=Config.MONGODB_DB_NAME,
                collection_name=Config.VOICE_COLLECTION_NAME,
                config=Config
            )
            
            app.register_blueprint(voice_bp)
            logger.info("✓ Voice Recognition blueprint registered")
            logger.info("  Routes:")
            logger.info("    POST /api/voice/register - Register new user")
            logger.info("    POST /api/voice/identify - Identify speaker")
            logger.info("    POST /api/voice/verify - Verify speaker identity")
            logger.info("    GET  /api/voice/users - Get all registered users")
            logger.info("    DELETE /api/voice/users/<name> - Delete user")
            
        except Exception as e:
            logger.error(f"✗ Voice Recognition blueprint registration failed: {e}")
            voice_recognition_ready = False
    else:
        logger.warning("⚠ Voice Recognition disabled (services not ready)")
    
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
            'message': 'Integrated Smart Wallet + Blind Assistant + Voice Recognition API',
            'version': '2.2.0',
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
                        'analytics': '/api/analytics/*',
                        'documents': '/api/document/*'
                    }
                },
                'integrated_face_detection': {
                    'status': 'active' if integrated_face_ready else 'unavailable',
                    'description': 'Unified live face detection for blind users',
                    'endpoints': [
                        '/api/integrated-face/quick-detect',
                        '/api/integrated-face/analyze',
                        '/api/integrated-face/health'
                    ] if integrated_face_ready else []
                },
                'voice_recognition': {
                    'status': 'active' if voice_recognition_ready else 'unavailable',
                    'description': 'Speaker identification and verification',
                    'endpoints': [
                        '/api/voice/register',
                        '/api/voice/identify',
                        '/api/voice/verify',
                        '/api/voice/users'
                    ] if voice_recognition_ready else [],
                    'mongodb': 'connected' if mongodb_ready else 'disconnected',
                    'collection': Config.VOICE_COLLECTION_NAME if voice_recognition_ready else None
                },
                'blind_assistant': {
                    'status': blind_assistant_status,
                    'description': 'Age/gender detection, face recognition, attribute detection',
                    'endpoints': {
                        'age_gender': '/api/age-gender/detect' if age_gender_available else 'disabled',
                        'face_recognition': '/api/face-recognition/*' if face_recognition_available else 'disabled',
                        'attributes': '/api/attributes/detect' if attributes_available else 'disabled'
                    }
                }
            },
            'documentation': {
                'health_check': '/health',
                'smart_wallet_health': '/health/wallet',
                'blind_assistant_health': '/health/assistant',
                'voice_recognition_health': '/health/voice'
            }
        }), 200
    
    @app.route('/health', methods=['GET'])
    def health_check():
        """Complete health check for all systems"""
        return jsonify({
            'status': 'healthy',
            'database': Config.DATABASE_TYPE,
            'systems': {
                'smart_wallet': {
                    'database': 'connected',
                    'tesseract': tesseract_ok,
                    'services': ['bill_scanner', 'wallet', 'currency_detector', 'expense_analytics']
                },
                'voice_recognition': {
                    'status': 'active' if voice_recognition_ready else 'disabled',
                    'mongodb': 'connected' if mongodb_ready else 'disconnected',
                    'model': Config.VOICE_MODEL_NAME if voice_recognition_ready else None
                },
                'blind_assistant': {
                    'services': [s for s, a in [
                        ('age_gender', age_gender_available),
                        ('face_recognition', face_recognition_available),
                        ('attributes', attributes_available)
                    ] if a],
                    'mongodb': 'connected' if mongodb_ready else 'not required'
                }
            }
        }), 200
    
    @app.route('/health/voice', methods=['GET'])
    def health_voice():
        """Voice Recognition specific health check"""
        if not voice_recognition_ready:
            return jsonify({
                'system': 'voice_recognition',
                'status': 'disabled',
                'message': 'Voice recognition services not initialized'
            }), 503
        
        try:
            # Test MongoDB connection
            mongo_client = MongoClient(Config.MONGODB_URI, serverSelectionTimeoutMS=2000)
            mongo_client.admin.command('ping')
            db = mongo_client[Config.MONGODB_DB_NAME]
            user_count = db[Config.VOICE_COLLECTION_NAME].count_documents({})
            mongo_client.close()
            
            return jsonify({
                'system': 'voice_recognition',
                'status': 'healthy',
                'mongodb': 'connected',
                'database': Config.MONGODB_DB_NAME,
                'collection': Config.VOICE_COLLECTION_NAME,
                'registered_users': user_count,
                'configuration': {
                    'similarity_threshold': Config.SIMILARITY_THRESHOLD,
                    'min_audio_duration': f"{Config.MIN_AUDIO_DURATION}s",
                    'max_audio_duration': f"{Config.MAX_AUDIO_DURATION}s",
                    'model': Config.VOICE_MODEL_NAME
                }
            }), 200
            
        except Exception as e:
            return jsonify({
                'system': 'voice_recognition',
                'status': 'unhealthy',
                'error': str(e)
            }), 503
    
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
                'voice_recognition': '/api/voice/*',
                'blind_assistant': '/api/age-gender, /api/face-recognition, /api/attributes'
            }
        }), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        logger.error(f"Internal Server Error: {error}")
        return jsonify({
            'error': 'Internal server error',
            'message': 'An unexpected error occurred. Please check server logs.'
        }), 500
    
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
    print("  🚀 INTEGRATED SYSTEM")
    print("  Smart Wallet + Blind Assistant + Voice Recognition")
    print("="*80)
    print(f"\n  💾 DATABASE: {Config.DATABASE_TYPE.upper()}")
    print(f"  🔗 MONGODB: {Config.MONGODB_DB_NAME}")
    print("\n  📦 FEATURES:")
    print("     ✓ Bill Scanner (YOLO + OCR)")
    print("     ✓ Wallet Management")
    print("     ✓ Currency Detection")
    print("     ✓ Expense Analytics Dashboard")
    print("     ✓ Voice Recognition (Register/Identify)")
    if age_gender_available:
        print("     ✓ Age & Gender Detection")
    if face_recognition_available:
        print("     ✓ Face Recognition")
    if attributes_available:
        print("     ✓ Attribute Detection")
    
    print("\n  🌐 Server Info:")
    print(f"     URL: http://{Config.API_HOST}:{Config.API_PORT}")
    print(f"     Debug Mode: {Config.DEBUG}")
    print("\n  📚 API Documentation:")
    print("     Root: /")
    print("     Health: /health, /health/voice")
    print("     Smart Wallet: /api/bill, /api/wallet, /api/currency")
    print("     Voice Recognition: /api/voice/register, /api/voice/identify")
    print("="*80 + "\n")
    
    app.run(
        host=Config.API_HOST,
        port=Config.API_PORT,
        debug=Config.DEBUG,
        threaded=True
    )
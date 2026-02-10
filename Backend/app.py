# FILE: app.py
# ============================================================================
# INTEGRATED MAIN APPLICATION
# Smart Wallet + Blind Assistant System
# ============================================================================

from flask import Flask, jsonify
from flask_cors import CORS
from pathlib import Path
import logging
import os

# Configuration
from config import Config

# Database initialization
from app.models.database import init_all_databases, ensure_database_ready
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

# ============================================================================
# IMPORT ALL BLUEPRINTS
# ============================================================================

# Smart Wallet Routes
from app.routes.bill_routes import bill_bp
from app.routes.wallet_routes import wallet_bp
from app.routes.currency_routes import currency_bp
from app.routes.legacy_routes import legacy_bp

# Face Detection - INTEGRATED
from routes.integrated_face_routes import integrated_face_bp, init_integrated_service

# Face Detection - Individual
from routes.age_gender_routes import age_gender_bp
from routes.face_recognition_routes import face_recognition_bp
from routes.attributes_routes import attributes_bp

# Voice Recognition - NEW FEATURE
from routes.voice_routes import init_voice_routes
from services.voice_service import VoiceRecognitionService
from utils.audio_processor import AudioProcessor

# ============================================================================
# LOGGING SETUP
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ============================================================================
# GLOBAL SERVICES (Voice Recognition)
# ============================================================================
voice_service = None
audio_processor = None

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
    
    # Initialize Smart Wallet Database
    logger.info("Initializing Smart Wallet Database...")
    init_all_databases()
    ensure_database_ready()
    logger.info("✓ Smart Wallet Database ready")

    # ========================================================================
    # INITIALIZE MONGODB (Shared for Face + Voice Recognition)
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
        logger.error(f"  Error details: {str(e)}")
        mongodb_ready = False
    
    # Integrated Face Detection setup
    integrated_face_ready = False
    try:
        logger.info("Initializing Integrated Face Detection...")
        init_integrated_service(Config.MONGODB_URI)
        integrated_face_ready = True
        logger.info("  ✓ Integrated Face Detection ready")
    except Exception as e:
        logger.error(f"✗ Integrated Face Detection failed: {e}")
        logger.error(f"  Error details: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        integrated_face_ready = False
    
    # ========================================================================
    # INITIALIZE VOICE RECOGNITION SERVICE
    # ========================================================================
    global voice_service, audio_processor
    voice_ready = False
    
    if mongodb_ready:
        try:
            logger.info("Initializing Voice Recognition Service...")
            
            # Initialize audio processor
            logger.info("  - Loading Audio Processor...")
            audio_processor = AudioProcessor(target_sr=16000)
            logger.info("    ✓ Audio Processor ready")
            
            # Initialize voice recognition model
            logger.info("  - Loading Voice Recognition Model...")
            logger.info("    (First run: Downloads ~500MB, takes 2-5 minutes)")
            logger.info("    (Subsequent runs: Loads from cache in 10-20 seconds)")
            
            voice_service = VoiceRecognitionService(
                model_name=Config.MODEL_NAME,
                model_save_dir=Config.MODEL_SAVE_DIR
            )
            
            logger.info("  ✓ Voice Recognition Service ready")
            voice_ready = True
            
        except Exception as e:
            logger.error(f"✗ Voice Recognition initialization failed: {e}")
            logger.error(f"  Error details: {str(e)}")
            import traceback
            logger.error(traceback.format_exc())
            voice_ready = False
    else:
        logger.warning("⚠  Skipping Voice Recognition initialization (MongoDB not ready)")
    
    # Verify Tesseract for OCR
    tesseract_ok = Config.verify_tesseract()
    
    logger.info("="*80)
    
    # ========================================================================
    # REGISTER BLUEPRINTS
    # ========================================================================
    
    logger.info("Registering blueprints...")

    # Smart Wallet Blueprints
    app.register_blueprint(bill_bp)          # /api/bill/*
    app.register_blueprint(wallet_bp)        # /api/wallet/*
    app.register_blueprint(currency_bp)      # /api/currency/*
    app.register_blueprint(legacy_bp)        # Legacy endpoints (backward compatibility)
    logger.info("  ✓ Smart Wallet")

        # Integrated Face Detection - NEW PRIMARY FEATURE
    # Always register the blueprint, even if initialization failed
    app.register_blueprint(integrated_face_bp, url_prefix='/api/integrated-face')
    
    if integrated_face_ready:
        logger.info("  ✓ Integrated Face Detection (LIVE) - ACTIVE")
        logger.info("     URL: /api/integrated-face/*")
        logger.info("     Routes:")
        logger.info("       POST   /api/integrated-face/quick-detect")
        logger.info("       POST   /api/integrated-face/analyze")
        logger.info("       GET    /api/integrated-face/health")
    else:
        logger.warning("  ⚠  Integrated Face Detection REGISTERED but SERVICE NOT READY")
        logger.warning("     Routes will return 503 errors")
    
    # Debug: Print all registered routes
    logger.info("\n" + "="*80)
    logger.info("ALL REGISTERED ROUTES:")
    logger.info("="*80)
    for rule in app.url_map.iter_rules():
        logger.info(f"  {list(rule.methods)} {rule.rule}")
    logger.info("="*80 + "\n")
    
    # Blind Assistant Blueprints
    app.register_blueprint(age_gender_bp, url_prefix='/api/age-gender')
    app.register_blueprint(face_recognition_bp, url_prefix='/api/face-recognition')
    app.register_blueprint(attributes_bp, url_prefix='/api/attributes')
    logger.info("  ✓ Individual Face Features")

    # Voice Recognition Blueprint
    if voice_ready and mongodb_ready:
        voice_bp = init_voice_routes(
            audio_processor=audio_processor,
            voice_service=voice_service,
            mongo_uri=Config.MONGODB_URI,
            db_name=Config.VOICE_DATABASE_NAME,
            config=Config
        )
        app.register_blueprint(voice_bp)
        logger.info("  ✓ Voice Recognition - ACTIVE")
        logger.info("     URL: /api/voice/*")
        logger.info("     Routes:")
        logger.info("       POST   /api/voice/register")
        logger.info("       POST   /api/voice/identify")
        logger.info("       POST   /api/voice/verify")
        logger.info("       GET    /api/voice/users")
        logger.info("       DELETE /api/voice/users/<name>")
    else:
        logger.warning("  ⚠  Voice Recognition NOT INITIALIZED (MongoDB or service failed)")
    
    
    logger.info("✓ All blueprints registered")
    
    # ========================================================================
    # ROOT ENDPOINTS
    # ========================================================================
    
    @app.route('/', methods=['GET'])
    def root():
        """Root endpoint - API overview"""
        return jsonify({
            'message': 'Integrated Smart Wallet + Blind Assistant API',
            'version': '2.0.0',
            'status': 'running',
            'systems': {
                'smart_wallet': {
                    'status': 'active',
                    'description': 'Bill scanning, wallet management, currency detection',
                    'endpoints': {
                        'bills': '/api/bill/*',
                        'wallet': '/api/wallet/*',
                        'currency': '/api/currency/*',
                        'legacy': '/scan_bill_display_only, /get_wallet_balance, etc.'
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
                'individual_face_features': {
                    'status': 'active',
                    'description': 'Legacy individual features',
                    'endpoints': [
                        '/api/age-gender/detect',
                        '/api/face-recognition/register',
                        '/api/face-recognition/recognize',
                        '/api/attributes/detect'
                    ]
                },
                'voice_recognition': {
                    'status': 'active' if voice_ready else 'unavailable',
                    'description': 'Speaker identification and verification',
                    'endpoints': [
                        '/api/voice/register',
                        '/api/voice/identify',
                        '/api/voice/verify',
                        '/api/voice/users'
                    ] if voice_ready else [],
                    'model': Config.MODEL_NAME if voice_ready else None
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
        return jsonify({
            'status': 'healthy',
            'systems': {
                'smart_wallet': {
                    'database': 'connected',
                    'tesseract': tesseract_ok,
                    'services': ['bill_scanner', 'wallet', 'currency_detector']
                },
                'blind_assistant': {
                    'services': ['age_gender', 'face_recognition', 'attributes'],
                    'mongodb': 'connected'
                },
                'voice_recognition': {
                    'service': 'active' if voice_ready else 'inactive',
                    'mongodb': 'connected' if mongodb_ready else 'disconnected',
                    'model': Config.MODEL_NAME if voice_ready else None
                }
            }
        }), 200
    
    @app.route('/health/wallet', methods=['GET'])
    def health_wallet():
        """Smart Wallet specific health check"""
        return jsonify({
            'system': 'smart_wallet',
            'status': 'healthy',
            'tesseract': tesseract_ok,
            'database': 'connected',
            'services': {
                'bill_scanner': 'active',
                'wallet_service': 'active',
                'currency_detector': 'active',
                'ocr_service': 'active'
            }
        }), 200
    
    @app.route('/health/assistant', methods=['GET'])
    def health_assistant():
        """Blind Assistant specific health check"""
        return jsonify({
            'system': 'blind_assistant',
            'status': 'healthy',
            'mongodb': 'connected',
            'services': {
                'age_gender_detection': 'active',
                'face_recognition': 'active',
                'attributes_detection': 'active'
            }
        }), 200
    
    @app.route('/health/voice', methods=['GET'])
    def health_voice():
        """Voice Recognition specific health check"""
        if not voice_ready:
            return jsonify({
                'system': 'voice_recognition',
                'status': 'unavailable',
                'error': 'Voice recognition service not initialized'
            }), 503
        
        try:
            # Get user count
            mongo_client = MongoClient(Config.MONGODB_URI, serverSelectionTimeoutMS=2000)
            db = mongo_client[Config.VOICE_DATABASE_NAME]
            user_count = db[Config.VOICE_COLLECTION_NAME].count_documents({})
            mongo_client.close()
            
            import torch
            
            return jsonify({
                'system': 'voice_recognition',
                'status': 'healthy',
                'mongodb': {
                    'status': 'connected',
                    'database': Config.VOICE_DATABASE_NAME,
                    'collection': Config.VOICE_COLLECTION_NAME,
                    'registered_users': user_count
                },
                'model': {
                    'name': Config.MODEL_NAME,
                    'device': 'GPU' if torch.cuda.is_available() else 'CPU'
                },
                'configuration': {
                    'similarity_threshold': Config.SIMILARITY_THRESHOLD,
                    'min_audio_duration': f"{Config.MIN_AUDIO_DURATION}s",
                    'max_audio_duration': f"{Config.MAX_AUDIO_DURATION}s",
                    'allowed_formats': list(Config.ALLOWED_AUDIO_EXTENSIONS)
                }
            }), 200
            
        except Exception as e:
            return jsonify({
                'system': 'voice_recognition',
                'status': 'error',
                'error': str(e)
            }), 503
    
    # ========================================================================
    # ERROR HANDLERS
    # ========================================================================
    
    @app.errorhandler(404)
    def not_found(error):
        """Handle 404 errors"""
        return jsonify({
            'error': 'Endpoint not found',
            'message': 'The requested URL was not found on the server',
            'available_systems': {
                'smart_wallet': '/api/bill, /api/wallet, /api/currency',
                'blind_assistant': '/api/age-gender, /api/face-recognition, /api/attributes',
                'voice_recognition': '/api/voice'
            }
        }), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        """Handle 500 errors"""
        logger.error(f"Internal Server Error: {error}")
        return jsonify({
            'error': 'Internal server error',
            'message': 'An unexpected error occurred. Please check server logs.'
        }), 500
    
    @app.errorhandler(400)
    def bad_request(error):
        """Handle 400 errors"""
        return jsonify({
            'error': 'Bad request',
            'message': 'The request could not be understood by the server'
        }), 400
    
    @app.errorhandler(413)
    def request_entity_too_large(error):
        """Handle file too large errors"""
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
    print("\n  📦 SMART WALLET FEATURES:")
    print("     ✓ Bill Scanner (YOLO + OCR)")
    print("     ✓ Wallet Management")
    print("     ✓ Currency Detection")
    print("     ✓ Transaction Tracking")
    print("     ✓ Category Classification")
    print("\n  👁️  BLIND ASSISTANT FEATURES:")
    print("     ✓ Age & Gender Detection")
    print("     ✓ Face Recognition")
    print("     ✓ Attribute Detection (glasses, masks, etc.)")
    print("     ✓ Person Position & Distance Estimation")
    print("\n  🌐 Server Info:")
    print(f"     URL: http://{Config.API_HOST}:{Config.API_PORT}")
    print(f"     Debug Mode: {Config.DEBUG}")
    print("\n  📚 API Documentation:")
    print("     Root: /")
    print("     Health: /health")
    print("     Smart Wallet: /api/bill, /api/wallet, /api/currency")
    print("     Blind Assistant: /api/age-gender, /api/face-recognition, /api/attributes")
    print("     Voice Recognition: /api/voice")
    print("="*80 + "\n")
    
    app.run(
        host=Config.API_HOST,
        port=Config.API_PORT,
        debug=Config.DEBUG,
        threaded=True
    )
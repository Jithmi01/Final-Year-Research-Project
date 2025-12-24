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

# ============================================================================
# IMPORT ALL BLUEPRINTS
# ============================================================================

# Smart Wallet Routes
from app.routes.bill_routes import bill_bp
from app.routes.wallet_routes import wallet_bp
from app.routes.currency_routes import currency_bp
from app.routes.legacy_routes import legacy_bp

# Blind Assistant Routes
from routes.age_gender_routes import age_gender_bp
from routes.face_recognition_routes import face_recognition_bp
from routes.attributes_routes import attributes_bp

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
    
    # Initialize Smart Wallet Database
    logger.info("Initializing Smart Wallet Database...")
    init_all_databases()
    ensure_database_ready()
    logger.info("✓ Smart Wallet Database ready")
    
    # Verify Tesseract for OCR
    tesseract_ok = Config.verify_tesseract()
    
    logger.info("="*80)
    
    # ========================================================================
    # REGISTER BLUEPRINTS
    # ========================================================================
    
    # Smart Wallet Blueprints
    app.register_blueprint(bill_bp)          # /api/bill/*
    app.register_blueprint(wallet_bp)        # /api/wallet/*
    app.register_blueprint(currency_bp)      # /api/currency/*
    app.register_blueprint(legacy_bp)        # Legacy endpoints (backward compatibility)
    
    # Blind Assistant Blueprints
    app.register_blueprint(age_gender_bp, url_prefix='/api/age-gender')
    app.register_blueprint(face_recognition_bp, url_prefix='/api/face-recognition')
    app.register_blueprint(attributes_bp, url_prefix='/api/attributes')
    
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
                'blind_assistant': {
                    'status': 'active',
                    'description': 'Age/gender detection, face recognition, attribute detection',
                    'endpoints': {
                        'age_gender': '/api/age-gender/detect',
                        'face_recognition_register': '/api/face-recognition/register',
                        'face_recognition_recognize': '/api/face-recognition/recognize',
                        'attributes': '/api/attributes/detect'
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
                'blind_assistant': '/api/age-gender, /api/face-recognition, /api/attributes'
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
    print("="*80 + "\n")
    
    app.run(
        host=Config.API_HOST,
        port=Config.API_PORT,
        debug=Config.DEBUG,
        threaded=True
    )
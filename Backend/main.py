# FILE: app/main.py
# Flask application initialization
# ============================================================================

"""
Main Flask Application
Initialize app and register all routes
"""

from flask import Flask, jsonify
from flask_cors import CORS
from config.settings import API_HOST, API_PORT, DEBUG, verify_tesseract
from models.database import init_all_databases, ensure_database_ready

# Import blueprints
from routes.bill_routes import bill_bp
from routes.wallet_routes import wallet_bp
from routes.currency_routes import currency_bp
from routes.legacy_routes import legacy_bp

def create_app():
    app = Flask(__name__)
    
    # Enable CORS
    CORS(app)
    
    # Initialize database
    init_all_databases()
    ensure_database_ready()
    
    # Verify Tesseract
    tesseract_ok = verify_tesseract()
    
    # Register NEW blueprints
    app.register_blueprint(bill_bp)
    app.register_blueprint(wallet_bp)
    app.register_blueprint(currency_bp)
    
    # ⭐ Register LEGACY blueprint for backward compatibility
    app.register_blueprint(legacy_bp)
    
    # ========================================================================
    # ROOT ENDPOINTS
    # ========================================================================
    
    @app.route('/', methods=['GET'])
    def root():
        """Root endpoint"""
        return jsonify({
            'message': 'Smart Wallet Backend API',
            'version': '1.0.0',
            'status': 'running',
            'endpoints': {
                'health': '/health',
                'bills': '/api/bill/*',
                'wallet': '/api/wallet/*',
                'currency': '/api/currency/*'
            }
        })
    
    @app.route('/health', methods=['GET'])
    def health_check():
        """Health check endpoint"""
        return jsonify({
            'status': 'healthy',
            'tesseract': tesseract_ok,
            'database': 'connected',
            'message': 'All systems operational'
        })
    
    # ========================================================================
    # ERROR HANDLERS
    # ========================================================================
    
    @app.errorhandler(404)
    def not_found(error):
        """Handle 404 errors"""
        return jsonify({
            'error': 'Endpoint not found',
            'message': 'The requested URL was not found on the server'
        }), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        """Handle 500 errors"""
        return jsonify({
            'error': 'Internal server error',
            'message': 'An unexpected error occurred'
        }), 500
    
    @app.errorhandler(400)
    def bad_request(error):
        """Handle 400 errors"""
        return jsonify({
            'error': 'Bad request',
            'message': 'The request could not be understood by the server'
        }), 400
    
    return app

# Create app instance
app = create_app()

if __name__ == "__main__":
    print("=" * 80)
    print("  🚀 SMART WALLET BACKEND API")
    print("=" * 80)
    print(f"  ✓ Bill Scanner: Ready")
    print(f"  ✓ Wallet Service: Ready")
    print(f"  ✓ Currency Detection: Ready")
    print(f"  ✓ Database: Initialized")
    print("=" * 80)
    
    app.run(host=API_HOST, port=API_PORT, debug=DEBUG)
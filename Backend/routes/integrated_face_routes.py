# FILE: routes/integrated_face_routes.py
# Unified live face detection endpoint for blind users

from flask import Blueprint, request, jsonify
from werkzeug.utils import secure_filename
import os
from services.integrated_face_service import IntegratedFaceService
from config import Config
import logging

logger = logging.getLogger(__name__)

integrated_face_bp = Blueprint('integrated_face', __name__)

# Initialize service (will be set in app.py)
integrated_service = None

def init_integrated_service(mongodb_uri):
    """Initialize the integrated service with MongoDB URI"""
    global integrated_service
    integrated_service = IntegratedFaceService(mongodb_uri)
    logger.info("✓ Integrated Face Service initialized")

UPLOAD_FOLDER = Config.UPLOAD_FOLDER
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@integrated_face_bp.route('/quick-detect', methods=['POST'])
def quick_face_detect():
    """
    Quick face detection for voice feedback.
    Used when camera is focusing to give "face detected" feedback.
    
    Returns:
    {
        'face_detected': true/false,
        'message': 'Face detected' or 'No face detected'
    }
    """
    try:
        # Check if service is initialized
        if integrated_service is None:
            logger.error("Integrated service not initialized")
            return jsonify({'error': 'Service not initialized'}), 503
        
        if 'image' not in request.files:
            return jsonify({'error': 'No image provided'}), 400
        
        file = request.files['image']
        if file.filename == '':
            return jsonify({'error': 'Empty filename'}), 400
        
        if not allowed_file(file.filename):
            return jsonify({'error': 'Invalid file type'}), 400
        
        # Save temporary file
        filename = secure_filename(file.filename)
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        file.save(filepath)
        
        try:
            # Quick face detection
            face_detected = integrated_service.detect_face_in_frame(filepath)
            
            return jsonify({
                'face_detected': face_detected,
                'message': 'Face detected' if face_detected else 'No face detected'
            }), 200
            
        finally:
            # Clean up
            if os.path.exists(filepath):
                os.remove(filepath)
    
    except Exception as e:
        logger.error(f"Quick detect error: {e}")
        return jsonify({'error': str(e)}), 500

@integrated_face_bp.route('/analyze', methods=['POST'])
def analyze_face():
    """
    Complete face analysis when user taps screen.
    
    Workflow:
    1. Detect if face exists
    2. Try face recognition
    3. If known → return name + last seen + distance + position
    4. If unknown → return age + gender + attributes + distance + position
    
    Returns:
    {
        'face_detected': bool,
        'person_type': 'known' | 'unknown',
        'announcement': str,  // Text for voice output
        'data': {}  // Detailed results
    }
    """
    try:
        # Check if service is initialized
        if integrated_service is None:
            logger.error("Integrated service not initialized")
            return jsonify({'error': 'Service not initialized'}), 503
        
        if 'image' not in request.files:
            return jsonify({'error': 'No image provided'}), 400
        
        file = request.files['image']
        if file.filename == '':
            return jsonify({'error': 'Empty filename'}), 400
        
        if not allowed_file(file.filename):
            return jsonify({'error': 'Invalid file type'}), 400
        
        # Save temporary file
        filename = secure_filename(file.filename)
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        file.save(filepath)
        
        try:
            # Complete analysis
            logger.info("Starting complete face analysis...")
            result = integrated_service.analyze_face(filepath)
            
            # Log the result
            if result.get('face_detected'):
                person_type = result.get('person_type', 'unknown')
                logger.info(f"Analysis complete: {person_type} person")
            else:
                logger.warning("No face detected in analysis")
            
            return jsonify(result), 200
            
        finally:
            # Clean up
            if os.path.exists(filepath):
                os.remove(filepath)
    
    except Exception as e:
        logger.error(f"Analysis error: {e}")
        return jsonify({
            'face_detected': False,
            'error': str(e),
            'announcement': 'Error analyzing face. Please try again.'
        }), 500

@integrated_face_bp.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'integrated_face_detection',
        'components': {
                'face_recognition': 'active',
                'age_gender': 'active',
            'attributes': 'active'
        }
    }), 200
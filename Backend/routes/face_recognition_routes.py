# routes/face_recognition_routes.py
# FIXED: Lazy MongoDB initialization to prevent DNS timeout on module import

from flask import Blueprint, request, jsonify
from werkzeug.utils import secure_filename
import os
import logging
from datetime import datetime
from config import Config

UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

face_recognition_bp = Blueprint('face_recognition', __name__)

# ============================================================================
# LAZY SERVICE INITIALIZATION (FIXES DNS TIMEOUT)
# ============================================================================
service = None
_service_init_error = None
logger = logging.getLogger(__name__)

def get_service():
    """
    Lazy initialization of FaceRecognitionService
    Only connects to MongoDB when routes are actually called
    This prevents DNS timeout during module import
    """
    global service, _service_init_error
    
    # Return existing service if already initialized
    if service is not None:
        return service
    
    # If previous initialization failed, raise that error
    if _service_init_error is not None:
        raise _service_init_error
    
    # Initialize service
    try:
        from services.face_recognition_service import FaceRecognitionService
        logger.info("Initializing Face Recognition Service...")
        service = FaceRecognitionService(Config.MONGODB_URI)
        logger.info("✓ Face Recognition Service initialized successfully")
        return service
    except Exception as e:
        _service_init_error = e
        logger.error(f"✗ Failed to initialize Face Recognition Service: {e}")
        raise

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# ============================================================================
# ROUTES
# ============================================================================

@face_recognition_bp.route('/register', methods=['POST'])
def register_person():
    """Register a new person with face images"""
    try:
        svc = get_service()  # Lazy init
        
        name = request.form.get('name')
        if not name:
            return jsonify({'error': 'Name required'}), 400
        
        files = [request.files[f'image{i}'] for i in range(1, 6) if f'image{i}' in request.files]
        if not files:
            return jsonify({'error': 'At least 1 image required'}), 400
        
        paths = []
        for file in files:
            filename = secure_filename(file.filename)
            path = os.path.join(UPLOAD_FOLDER, filename)
            file.save(path)
            paths.append(path)
        
        result = svc.register_person(name, paths)
        
        # Clean up uploaded files
        for p in paths:
            if os.path.exists(p):
                os.remove(p)
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Registration error: {e}")
        return jsonify({'error': str(e)}), 500

@face_recognition_bp.route('/recognize', methods=['POST'])
def recognize_person():
    """Recognize a person from an image"""
    try:
        svc = get_service()  # Lazy init
        
        if 'image' not in request.files:
            return jsonify({'error': 'No image'}), 400
        
        file = request.files['image']
        path = os.path.join(UPLOAD_FOLDER, secure_filename(file.filename))
        file.save(path)
        
        result = svc.recognize_from_image(path)
        
        if os.path.exists(path):
            os.remove(path)
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Recognition error: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================
# PEOPLE MANAGEMENT ENDPOINTS
# ============================================================================

@face_recognition_bp.route('/people', methods=['GET'])
def get_registered_people():
    """Get all registered people with their details"""
    try:
        svc = get_service()  # Lazy init
        
        people_list = svc.get_all_registered_people()
        return jsonify({
            'success': True,
            'people': people_list,
            'total': len(people_list)
        }), 200
        
    except Exception as e:
        logger.error(f"Error retrieving people: {e}")
        return jsonify({
            'error': 'Failed to retrieve people',
            'message': str(e)
        }), 500

@face_recognition_bp.route('/person/<person_id>', methods=['GET'])
def get_person_details(person_id):
    """Get details of a specific person"""
    try:
        svc = get_service()  # Lazy init
        
        person = svc.get_person_by_id(person_id)
        if person:
            return jsonify({
                'success': True,
                'person': person
            }), 200
        else:
            return jsonify({
                'error': 'Person not found'
            }), 404
            
    except Exception as e:
        logger.error(f"Error retrieving person: {e}")
        return jsonify({
            'error': 'Failed to retrieve person',
            'message': str(e)
        }), 500

@face_recognition_bp.route('/person/<person_id>', methods=['DELETE'])
def delete_person(person_id):
    """Delete a registered person"""
    try:
        svc = get_service()  # Lazy init
        
        result = svc.delete_person(person_id)
        if result['success']:
            return jsonify(result), 200
        else:
            return jsonify(result), 404
            
    except Exception as e:
        logger.error(f"Error deleting person: {e}")
        return jsonify({
            'error': 'Failed to delete person',
            'message': str(e)
        }), 500

@face_recognition_bp.route('/person/<person_id>', methods=['PUT'])
def update_person(person_id):
    """Update person's name"""
    try:
        svc = get_service()  # Lazy init
        
        data = request.get_json()
        new_name = data.get('name')
        
        if not new_name:
            return jsonify({'error': 'Name required'}), 400
        
        result = svc.update_person_name(person_id, new_name)
        if result['success']:
            return jsonify(result), 200
        else:
            return jsonify(result), 404
            
    except Exception as e:
        logger.error(f"Error updating person: {e}")
        return jsonify({
            'error': 'Failed to update person',
            'message': str(e)
        }), 500

@face_recognition_bp.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    try:
        svc = get_service()  # Lazy init
        return jsonify({
            'status': 'healthy',
            'service': 'face_recognition',
            'mongodb': 'connected'
        }), 200
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'service': 'face_recognition',
            'error': str(e)
        }), 503
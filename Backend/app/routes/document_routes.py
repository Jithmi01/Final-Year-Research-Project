# ============================================================================
# FILE: app/routes/document_routes.py
# Document Reading API Endpoints (FIXED VERSION)
# ============================================================================

from flask import Blueprint, request, jsonify
import traceback

# Import document reader
from app.services.document_reading_service import DocumentReader

# Create global document reader instance
_document_reader = None

def get_document_reader():
    """Get or create document reader instance"""
    global _document_reader
    if _document_reader is None:
        _document_reader = DocumentReader()
    return _document_reader

def validate_image_upload(image_file):
    """
    Validate uploaded image
    
    Returns:
        (bool, str): (is_valid, error_message)
    """
    if not image_file:
        return False, "No image file provided"
    
    if image_file.filename == '':
        return False, "Empty filename"
    
    # Check file size (max 10MB)
    image_file.seek(0, 2)  # Seek to end
    size = image_file.tell()
    image_file.seek(0)  # Reset to start
    
    if size > 10 * 1024 * 1024:  # 10MB
        return False, "Image too large (max 10MB)"
    
    if size == 0:
        return False, "Empty image file"
    
    return True, ""

document_bp = Blueprint('document', __name__, url_prefix='/api/document')

# ============================================================================
# CONTINUOUS READING MODE
# ============================================================================

@document_bp.route('/read_continuous', methods=['POST'])
def read_continuous():
    """
    Continuous reading mode - Real-time OCR
    
    Request: multipart/form-data with 'image' file
    
    Response:
    {
        'success': bool,
        'text': str,           # All text found
        'new_text': str,       # Only new text (for TTS)
        'should_speak': bool,  # True if should speak
        'voice_prompt': str    # What to speak
    }
    """
    print("[API] /read_continuous called")
    try:
        if 'image' not in request.files:
            print("[API] ✗ No image in request.files")
            return jsonify({
                'success': False,
                'error': 'No image provided',
                'voice_prompt': 'No image received. Try again.'
            }), 400
        
        image_file = request.files['image']
        print(f"[API] Image file received: {image_file.filename}, size: {len(image_file.read())} bytes")
        image_file.seek(0)  # Reset after reading size
        
        # Validate
        valid, message = validate_image_upload(image_file)
        if not valid:
            print(f"[API] ✗ Validation failed: {message}")
            return jsonify({
                'success': False,
                'error': message,
                'voice_prompt': 'Invalid image. Try again.'
            }), 400
        
        # Read image
        image_bytes = image_file.read()
        print(f"[API] Image bytes read: {len(image_bytes)}")
        
        # Process with document reader
        reader = get_document_reader()
        result = reader.read_continuous(image_bytes)
        
        print(f"[API] Result: success={result['success']}, should_speak={result.get('should_speak', False)}")
        
        return jsonify(result), 200
    
    except Exception as e:
        print(f"[API ERROR] read_continuous: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e),
            'voice_prompt': 'Error reading document. Try again.'
        }), 500


# ============================================================================
# CAPTURE MODE
# ============================================================================

@document_bp.route('/capture', methods=['POST'])
def capture_document():
    """
    Capture document for detailed analysis
    
    Request: multipart/form-data with 'image' file
    
    Response:
    {
        'success': bool,
        'document_id': str,
        'text': str,
        'lines': List[str],
        'metadata': Dict,
        'voice_prompt': str
    }
    """
    print("[API] /capture called")
    try:
        if 'image' not in request.files:
            print("[API] ✗ No image in request.files")
            return jsonify({
                'success': False,
                'error': 'No image provided',
                'voice_prompt': 'No image received. Try again.'
            }), 400
        
        image_file = request.files['image']
        print(f"[API] Image file received: {image_file.filename}")
        
        # Validate
        valid, message = validate_image_upload(image_file)
        if not valid:
            print(f"[API] ✗ Validation failed: {message}")
            return jsonify({
                'success': False,
                'error': message,
                'voice_prompt': 'Invalid image. Try again.'
            }), 400
        
        # Read image
        image_bytes = image_file.read()
        print(f"[API] Image bytes read: {len(image_bytes)}")
        
        # Capture document
        reader = get_document_reader()
        result = reader.capture_document(image_bytes)
        
        if result['success']:
            print(f"[API] ✓ Document captured: {result['document_id']}")
        else:
            print(f"[API] ✗ Capture failed: {result.get('error', 'Unknown error')}")
        
        return jsonify(result), 200 if result['success'] else 400
    
    except Exception as e:
        print(f"[API ERROR] capture: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e),
            'voice_prompt': 'Error capturing document. Try again.'
        }), 500


# ============================================================================
# VOICE Q&A
# ============================================================================

@document_bp.route('/ask', methods=['POST'])
def ask_question():
    """
    Voice-based Q&A about captured document
    
    Request JSON:
    {
        'question': str  # Voice-transcribed question
    }
    
    Response:
    {
        'success': bool,
        'answer': str,
        'confidence': float,
        'voice_prompt': str
    }
    """
    try:
        data = request.get_json()
        
        if not data or 'question' not in data:
            return jsonify({
                'success': False,
                'error': 'Missing question',
                'voice_prompt': 'Please ask a question about the document.'
            }), 400
        
        question = data['question'].strip()
        
        if not question:
            return jsonify({
                'success': False,
                'error': 'Empty question',
                'voice_prompt': 'Please ask a question about the document.'
            }), 400
        
        # Answer question
        reader = get_document_reader()
        result = reader.answer_question(question)
        
        print(f"[API Q&A] Q: '{question}' -> A: '{result.get('answer', 'N/A')[:50]}...'")
        
        return jsonify(result), 200 if result['success'] else 400
    
    except Exception as e:
        print(f"[API ERROR] ask: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e),
            'voice_prompt': 'Error answering question. Try again.'
        }), 500


# ============================================================================
# DOCUMENT MANAGEMENT
# ============================================================================

@document_bp.route('/get_current', methods=['GET'])
def get_current_document():
    """Get currently captured document"""
    try:
        reader = get_document_reader()
        doc = reader.get_current_document()
        
        if doc:
            return jsonify({
                'success': True,
                'has_document': True,
                'document': doc
            }), 200
        else:
            return jsonify({
                'success': True,
                'has_document': False,
                'document': None
            }), 200
    
    except Exception as e:
        print(f"[API ERROR] get_current: {e}")
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@document_bp.route('/clear', methods=['POST'])
def clear_document():
    """Clear currently captured document"""
    try:
        reader = get_document_reader()
        reader.clear_document()
        
        return jsonify({
            'success': True,
            'message': 'Document cleared',
            'voice_prompt': 'Document cleared. You can capture a new one.'
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] clear: {e}")
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
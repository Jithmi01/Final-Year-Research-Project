# ============================================================================
# FILE: app/routes/currency_routes.py
# Currency detection endpoints
# ============================================================================

"""
Currency Routes
API endpoints for currency note detection
"""

from flask import Blueprint, request, jsonify
import cv2
import numpy as np
import traceback
from app.services.currency_service import CurrencyDetector
from app.config.settings import validate_image_upload

currency_bp = Blueprint('currency', __name__, url_prefix='/api/currency')

@currency_bp.route('/detect', methods=['POST'])
def detect_currency():
    """Detect currency notes in image"""
    if 'image' not in request.files:
        return jsonify({'error': 'No image file'}), 400
    
    try:
        file = request.files['image']
        
        # Validate file
        valid, message = validate_image_upload(file)
        if not valid:
            return jsonify({'error': message}), 400
        
        # Read and decode image
        img_bytes = file.read()
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if frame is None:
            return jsonify({'error': 'Invalid image format'}), 400
        
        # Detect currency
        result = CurrencyDetector.detect(frame)
        
        return jsonify({
            'success': True,
            'message': result['message'],
            'detected_items': result['items'],
            'count': len(result['items'])
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /currency/detect: {e}")
        traceback.print_exc()
        
        return jsonify({'error': str(e)}), 500


@currency_bp.route('/detect_ar', methods=['POST'])
def detect_currency_ar():
    """Detect currency with AR positioning data"""
    if 'image' not in request.files:
        return jsonify({'error': 'No image file'}), 400
    
    try:
        file = request.files['image']
        
        # Read and decode image
        img_bytes = file.read()
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if frame is None:
            return jsonify({'error': 'Invalid image format'}), 400
        
        height, width = frame.shape[:2]
        
        # Detect with AR positions
        result = CurrencyDetector.detect_with_positions(frame)
        
        return jsonify({
            'success': True,
            'count': len(result['detections']),
            'detections': result['detections'],
            'image_size': {'width': width, 'height': height}
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /currency/detect_ar: {e}")
        traceback.print_exc()
        
        return jsonify({'error': str(e)}), 500

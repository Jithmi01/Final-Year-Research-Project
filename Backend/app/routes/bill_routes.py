# ============================================================================
# FILE: app/routes/bill_routes.py
# Bill scanning and management endpoints with camera guidance
# ============================================================================

"""
Bill Routes
API endpoints for bill scanning and management
"""

from flask import Blueprint, request, jsonify
import traceback
from app.services.bill_service import BillExtractor, BillRepository
from app.services.wallet_service import WalletService
from app.services.image_quality_checker import check_image_quality
from app.config.settings import validate_image_upload

bill_bp = Blueprint('bill', __name__, url_prefix='/api/bill')

@bill_bp.route('/scan', methods=['POST'])
def scan_bill():
    """Scan bill and extract information"""
    if 'image' not in request.files:
        return jsonify({'success': False, 'error': 'No image uploaded'}), 400
    
    try:
        file = request.files['image']
        
        # Validate file
        valid, message = validate_image_upload(file)
        if not valid:
            return jsonify({'success': False, 'error': message}), 400
        
        # Read image bytes
        image_bytes = file.read()
        
        # Process bill
        bill_info = BillExtractor.process_bill(image_bytes)
        
        if not bill_info:
            return jsonify({
                'success': False,
                'error': 'Failed to extract bill information'
            }), 400
        
        # Validate amount
        if bill_info['total_amount'] <= 0:
            return jsonify({
                'success': False,
                'error': 'Could not detect bill amount'
            }), 400
        
        # Generate confirmation message
        confirmation = BillExtractor.generate_confirmation(bill_info)
        
        print(f"[API] ✓ Bill scanned: {bill_info['vendor']} - Rs.{bill_info['total_amount']}")
        
        return jsonify({
            'success': True,
            'bill_info': bill_info,
            'confirmation_message': confirmation
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /bill/scan: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@bill_bp.route('/check_quality', methods=['POST'])
def check_quality():
    """
    Check image quality before scanning
    Used for real-time feedback in camera preview
    """
    try:
        if 'image' not in request.files:
            return jsonify({
                'success': False,
                'error': 'No image provided'
            }), 400
        
        image_file = request.files['image']
        image_bytes = image_file.read()
        
        # Analyze quality
        result = check_image_quality(image_bytes)
        
        return jsonify({
            'success': True,
            'quality_score': result['quality_score'],
            'is_acceptable': result['is_acceptable'],
            'voice_prompt': result['voice_prompt'],
            'recommendations': result['recommendations'],
            'checks': {
                'brightness_ok': result.get('brightness_ok', True),
                'sharpness_ok': result.get('sharpness_ok', True),
                'size_ok': result.get('size_ok', True),
                'contrast_ok': result.get('contrast_ok', True)
            },
            'issues': [
                {
                    'type': issue.type,
                    'severity': issue.severity,
                    'message': issue.message,
                    'voice_prompt': issue.voice_prompt
                }
                for issue in result['issues']
            ]
        })
    
    except Exception as e:
        print(f"[QUALITY CHECK ERROR] {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e),
            'voice_prompt': 'Error checking image quality. Try again.'
        }), 500


@bill_bp.route('/scan_with_guidance', methods=['POST'])
def scan_bill_with_guidance():
    """
    Enhanced bill scanning with quality check first
    """
    try:
        if 'image' not in request.files:
            return jsonify({
                'success': False,
                'error': 'No image provided'
            }), 400
        
        image_file = request.files['image']
        image_bytes = image_file.read()
        
        # Step 1: Check quality
        quality_result = check_image_quality(image_bytes)
        
        # Step 2: If quality is poor, return guidance without scanning
        if not quality_result['is_acceptable']:
            return jsonify({
                'success': False,
                'error': 'Image quality too poor',
                'quality_check': {
                    'quality_score': quality_result['quality_score'],
                    'voice_prompt': quality_result['voice_prompt'],
                    'recommendations': quality_result['recommendations']
                },
                'should_retry': True
            }), 400
        
        # Step 3: Quality is good, proceed with scanning
        bill_info = BillExtractor.process_bill(image_bytes)
        
        if not bill_info:
            return jsonify({
                'success': False,
                'error': 'Failed to extract bill information',
                'voice_prompt': 'Could not read bill. Try again with better lighting.'
            }), 400
        
        return jsonify({
            'success': True,
            'bill_info': bill_info,
            'quality_score': quality_result['quality_score'],
            'voice_prompt': f"Bill scanned successfully. {bill_info['vendor']}. Total: {bill_info['total_amount']} rupees."
        })
    
    except Exception as e:
        print(f"[SCAN WITH GUIDANCE ERROR] {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e),
            'voice_prompt': 'Scan failed. Please try again.'
        }), 500


@bill_bp.route('/save', methods=['POST'])
def save_bill():
    """Save scanned bill to database"""
    data = request.json
    
    if not data or 'bill_info' not in data:
        return jsonify({'success': False, 'error': 'Missing bill_info'}), 400
    
    try:
        bill_info = data['bill_info']
        
        # Save to database
        bill_id = BillRepository.save_bill(bill_info)
        
        if not bill_id:
            return jsonify({
                'success': False,
                'error': 'Failed to save bill'
            }), 500
        
        return jsonify({
            'success': True,
            'bill_id': bill_id,
            'message': 'Bill saved successfully'
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /bill/save: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@bill_bp.route('/confirm/<int:bill_id>', methods=['POST'])
def confirm_bill(bill_id):
    """Confirm bill and add to expenses"""
    try:
        success, message = BillRepository.confirm_bill(bill_id)
        
        if success:
            balance = WalletService.get_balance()
            return jsonify({
                'success': True,
                'message': message,
                'new_balance': balance
            }), 200
        else:
            return jsonify({
                'success': False,
                'error': message
            }), 400
    
    except Exception as e:
        print(f"[API ERROR] /bill/confirm: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@bill_bp.route('/recent', methods=['GET'])
def get_recent_bills():
    """Get recent bills"""
    try:
        limit = request.args.get('limit', 10, type=int)
        bills = BillRepository.get_recent_bills(limit)
        
        return jsonify({
            'success': True,
            'bills': bills,
            'count': len(bills)
        }), 200
    
    except Exception as e:
        print(f"[API ERROR] /bill/recent: {e}")
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
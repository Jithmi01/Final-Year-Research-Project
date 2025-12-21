# ============================================================================
# FILE: app/routes/legacy_routes.py (FIXED - Auto-saves bills to database)
# Backward compatibility routes with automatic bill saving
# ============================================================================

"""
Legacy Routes - Backward Compatibility
Maintains compatibility with existing Flutter frontend
NOW AUTOMATICALLY SAVES BILLS TO DATABASE
"""

from flask import Blueprint, request, jsonify
import traceback
from app.services.bill_service import BillExtractor, BillRepository
from app.services.wallet_service import WalletService, QuestionAnswerer, SummaryGenerator
from app.config.settings import validate_image_upload

legacy_bp = Blueprint('legacy', __name__)

# ============================================================================
# LEGACY BILL ENDPOINTS
# ============================================================================

@legacy_bp.route('/scan_bill_display_only', methods=['POST'])
def scan_bill_display_only():
    """
    LEGACY: Scan bill and return info (old endpoint name)
    NOW AUTOMATICALLY SAVES TO DATABASE!
    """
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
        
        # ⭐ AUTOMATICALLY SAVE BILL TO DATABASE
        bill_id = BillRepository.save_bill(bill_info)
        
        if bill_id:
            print(f"[LEGACY] ✓ Bill saved to database with ID: {bill_id}")
            bill_info['bill_id'] = bill_id  # Add bill_id to response
        else:
            print(f"[LEGACY] ⚠️  Bill processed but not saved (might be duplicate)")
        
        print(f"[LEGACY] ✓ Bill scanned: {bill_info['vendor']} - Rs.{bill_info['total_amount']}")
        
        return jsonify({
            'success': True,
            'bill_info': bill_info
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /scan_bill_display_only: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@legacy_bp.route('/save_bill', methods=['POST'])
def save_bill():
    """
    LEGACY: Explicitly save bill (for manual save requests)
    """
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
                'error': 'Failed to save bill (might be duplicate)'
            }), 500
        
        print(f"[LEGACY] ✓ Bill manually saved with ID: {bill_id}")
        
        return jsonify({
            'success': True,
            'bill_id': bill_id,
            'message': 'Bill saved successfully'
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /save_bill: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@legacy_bp.route('/confirm_bill/<int:bill_id>', methods=['POST'])
def confirm_bill(bill_id):
    """
    LEGACY: Confirm bill and add to expenses
    """
    try:
        success, message = BillRepository.confirm_bill(bill_id)
        
        if success:
            balance = WalletService.get_balance()
            print(f"[LEGACY] ✓ Bill {bill_id} confirmed and added to expenses")
            
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
        print(f"[LEGACY ERROR] /confirm_bill: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@legacy_bp.route('/get_recent_bills', methods=['GET'])
def get_recent_bills():
    """
    LEGACY: Get recent bills from database
    """
    try:
        limit = request.args.get('limit', 10, type=int)
        bills = BillRepository.get_recent_bills(limit)
        
        print(f"[LEGACY] ✓ Retrieved {len(bills)} recent bills")
        
        return jsonify({
            'success': True,
            'bills': bills,
            'count': len(bills)
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /get_recent_bills: {e}")
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============================================================================
# LEGACY WALLET ENDPOINTS
# ============================================================================

@legacy_bp.route('/get_wallet_balance', methods=['GET'])
def get_wallet_balance():
    """
    LEGACY: Get balance (old endpoint name)
    Maps to: /api/wallet/balance
    """
    try:
        balance = WalletService.get_balance()
        return jsonify({
            'balance': balance
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /get_wallet_balance: {e}")
        return jsonify({'error': str(e)}), 500


@legacy_bp.route('/add_wallet_transaction', methods=['POST'])
def add_wallet_transaction():
    """
    LEGACY: Add transaction (old endpoint name)
    Maps to: /api/wallet/transaction
    """
    data = request.json
    
    if not data or not all(k in data for k in ['amount', 'type', 'category']):
        return jsonify({'error': 'Missing required fields'}), 400
    
    try:
        amount = float(data['amount'])
        trans_type = data['type'].lower()
        category = data['category']
        description = data.get('description', '')
        
        # Validate
        if trans_type not in ['income', 'expense']:
            return jsonify({'error': 'Type must be income or expense'}), 400
        
        if amount <= 0:
            return jsonify({'error': 'Amount must be positive'}), 400
        
        # Add transaction
        success = WalletService.add_transaction(amount, trans_type, category, description)
        
        if success:
            return jsonify({
                'message': 'Transaction added',
                'new_balance': WalletService.get_balance()
            }), 200
        
        return jsonify({'error': 'Failed to add transaction'}), 500
    
    except ValueError:
        return jsonify({'error': 'Invalid amount format'}), 400
    except Exception as e:
        print(f"[LEGACY ERROR] /add_wallet_transaction: {e}")
        return jsonify({'error': str(e)}), 500


@legacy_bp.route('/ask_wallet_question', methods=['POST'])
def ask_wallet_question():
    """
    LEGACY: Ask wallet question (old endpoint name)
    Maps to: /api/wallet/question
    """
    data = request.json
    
    if not data or 'question' not in data:
        return jsonify({'error': 'Missing question'}), 400
    
    try:
        question = data['question']
        answer = QuestionAnswerer.process_question(question)
        
        return jsonify({
            'answer': answer
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /ask_wallet_question: {e}")
        return jsonify({'error': str(e)}), 500


@legacy_bp.route('/get_recent_transactions', methods=['GET'])
def get_recent_transactions():
    """
    LEGACY: Get recent transactions (old endpoint name)
    Maps to: /api/wallet/transactions/recent
    """
    try:
        limit = request.args.get('limit', 5, type=int)
        transactions = WalletService.get_recent_transactions(limit)
        
        return jsonify({
            'transactions': transactions
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /get_recent_transactions: {e}")
        return jsonify({'error': str(e)}), 500


@legacy_bp.route('/query_expenses', methods=['POST'])
def query_expenses():
    """
    LEGACY: Query expenses (old endpoint name)
    Simple implementation for basic queries
    """
    data = request.json
    
    if not data or 'query' not in data:
        return jsonify({'error': 'Missing query'}), 400
    
    try:
        query = data['query'].lower()
        
        # Simple query processing
        if 'grocery' in query or 'groceries' in query:
            # Get grocery expenses
            answer = "Query processing: Grocery expenses feature coming soon."
        elif 'transport' in query:
            answer = "Query processing: Transport expenses feature coming soon."
        else:
            answer = f"Query received: {query}. Advanced query processing coming soon."
        
        return jsonify({
            'answer': answer
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /query_expenses: {e}")
        return jsonify({'error': str(e)}), 500


@legacy_bp.route('/weekly_summary', methods=['GET'])
def weekly_summary():
    """
    LEGACY: Get weekly summary (old endpoint name)
    Maps to: /api/wallet/summary/weekly
    """
    try:
        summary = SummaryGenerator.generate_weekly()
        
        # Convert breakdown dict to list for compatibility
        breakdown_list = []
        if 'breakdown' in summary and summary['breakdown']:
            breakdown_list = [[cat, amt] for cat, amt in summary['breakdown'].items()]
        
        return jsonify({
            'message': summary['message'],
            'total_spending': summary['total_spending'],
            'total_income': summary.get('total_income', 0.0),
            'category_breakdown': breakdown_list,
            'comparison': 'Weekly comparison data',
            'week_start': summary.get('week_start', ''),
            'week_end': summary.get('week_end', '')
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /weekly_summary: {e}")
        return jsonify({'error': str(e)}), 500


@legacy_bp.route('/get_active_goal', methods=['GET'])
def get_active_goal():
    """
    LEGACY: Get active savings goal
    NOTE: Savings goal feature - basic implementation
    """
    try:
        # Placeholder response - implement if you need savings goals
        return jsonify({
            'has_goal': False,
            'goal': None,
            'message': 'No active savings goal'
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /get_active_goal: {e}")
        return jsonify({'error': str(e)}), 500


# ============================================================================
# LEGACY CURRENCY ENDPOINTS
# ============================================================================

@legacy_bp.route('/detect_currency', methods=['POST'])
def detect_currency():
    """
    LEGACY: Detect currency (old endpoint name)
    Maps to: /api/currency/detect
    """
    from app.services.currency_service import CurrencyDetector
    import cv2
    import numpy as np
    
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
        
        # Detect currency
        result = CurrencyDetector.detect(frame)
        
        return jsonify({
            'message': result['message'],
            'detected_items': result['items']
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /detect_currency: {e}")
        return jsonify({'error': str(e)}), 500


@legacy_bp.route('/detect_currency_ar', methods=['POST'])
def detect_currency_ar():
    """
    LEGACY: Detect currency with AR data (old endpoint name)
    Maps to: /api/currency/detect_ar
    """
    from app.services.currency_service import CurrencyDetector
    import cv2
    import numpy as np
    
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
        print(f"[LEGACY ERROR] /detect_currency_ar: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================
# ADD THIS TO: app/routes/legacy_routes.py
# Add this endpoint to test and view all saved bills
# ============================================================================

@legacy_bp.route('/test_get_all_bills', methods=['GET'])
def test_get_all_bills():
    """
    TEST ENDPOINT: Get ALL bills from database
    Use this to verify bills are being saved correctly
    """
    try:
        bills = BillRepository.get_all_bills()
        
        print(f"[TEST] Found {len(bills)} bills in database:")
        for bill in bills:
            print(f"  ID:{bill['id']} | {bill['vendor']} | Rs.{bill['total_amount']} | {bill['category']}")
        
        return jsonify({
            'success': True,
            'count': len(bills),
            'bills': bills,
            'message': f"Found {len(bills)} bills in database"
        }), 200
    
    except Exception as e:
        print(f"[TEST ERROR] /test_get_all_bills: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@legacy_bp.route('/test_database_info', methods=['GET'])
def test_database_info():
    """
    TEST ENDPOINT: Get database statistics
    Shows how many records in each table
    """
    try:
        from app.models.database import get_database_info
        
        info = get_database_info()
        
        print("[TEST] Database Info:")
        print(f"  Path: {info['database_path']}")
        for table, data in info['tables'].items():
            print(f"  {table}: {data['row_count']} rows")
        
        return jsonify({
            'success': True,
            'database_info': info
        }), 200
    
    except Exception as e:
        print(f"[TEST ERROR] /test_database_info: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
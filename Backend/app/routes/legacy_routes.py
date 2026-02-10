# ============================================================================
# FILE: app/routes/legacy_routes.py (COMPLETE WITH /add_transaction)
# Backward compatibility routes with automatic bill saving
# ============================================================================

"""
Legacy Routes - Backward Compatibility
Maintains compatibility with existing Flutter frontend
NOW AUTOMATICALLY SAVES BILLS TO DATABASE
"""

from flask import Blueprint, request, jsonify
import traceback
from datetime import datetime, timedelta
from app.services.bill_service import BillExtractor, BillRepository
from app.services.wallet_service import WalletService, QuestionAnswerer, SummaryGenerator
from app.config.settings import validate_image_upload
from app.services.expense_analytics_service import ExpenseAnalytics, ReportGenerator

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


# ============================================================================
# NEW: ADD TRANSACTION ENDPOINT (FOR AR CURRENCY DETECTOR)
# ============================================================================

@legacy_bp.route('/add_transaction', methods=['POST'])
def add_transaction():
    """
    Add a new transaction (for AR Currency Detector)
    Request JSON:
    {
        "amount": 5000.0,
        "type": "income",
        "category": "Currency",
        "description": "AR Currency Detection - 1 notes"
    }
    """
    try:
        data = request.get_json()
        
        # Validate required fields
        if not data:
            return jsonify({
                'status': 'error',
                'message': 'No data provided'
            }), 400
        
        amount = data.get('amount')
        trans_type = data.get('type')
        category = data.get('category', 'Other')
        description = data.get('description', '')
        
        # Validation
        if not amount:
            return jsonify({
                'status': 'error',
                'message': 'Amount is required'
            }), 400
        
        if not trans_type or trans_type not in ['income', 'expense']:
            return jsonify({
                'status': 'error',
                'message': 'Type must be "income" or "expense"'
            }), 400
        
        try:
            amount = float(amount)
            if amount <= 0:
                return jsonify({
                    'status': 'error',
                    'message': 'Amount must be greater than 0'
                }), 400
        except ValueError:
            return jsonify({
                'status': 'error',
                'message': 'Invalid amount format'
            }), 400
        
        # Add transaction using WalletService
        success = WalletService.add_transaction(
            amount=amount,
            trans_type=trans_type,
            category=category,
            description=description
        )
        
        if success:
            # Get updated balance
            balance = WalletService.get_balance()
            
            print(f"[LEGACY] ✓ Transaction added: {trans_type} Rs.{amount} ({category})")
            
            return jsonify({
                'status': 'success',
                'message': f'{trans_type.capitalize()} added successfully',
                'transaction': {
                    'amount': amount,
                    'type': trans_type,
                    'category': category,
                    'description': description
                },
                'balance': balance
            }), 200
        else:
            return jsonify({
                'status': 'error',
                'message': 'Failed to add transaction'
            }), 500
    
    except Exception as e:
        print(f"[LEGACY ERROR] /add_transaction: {e}")
        traceback.print_exc()
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500


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

@legacy_bp.route('/check_image_quality', methods=['POST'])
def check_image_quality_legacy():
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
        
        from app.services.image_quality_checker import check_image_quality
        
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


@legacy_bp.route('/scan_bill_with_guidance', methods=['POST'])
def scan_bill_with_guidance_legacy():
    """
    Enhanced bill scanning with quality check first
    """
    try:
        if 'image' not in request.files:
            return jsonify({
                'success': False,
                'error': 'No image provided'
            }), 400
        
        from app.services.image_quality_checker import check_image_quality
        
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
        
        # Auto-save bill to database
        bill_id = BillRepository.save_bill(bill_info)
        if bill_id:
            print(f"[LEGACY] ✓ Bill saved with guidance - ID: {bill_id}")
            bill_info['bill_id'] = bill_id
        
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
    
@legacy_bp.route('/get_expense_dashboard', methods=['POST'])
def get_expense_dashboard_legacy():
    """
    LEGACY: Get expense dashboard data (old endpoint name)
    Maps to: /api/analytics/dashboard
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'No data provided'
            }), 400
        
        period = data.get('period', 'weekly')
        date_str = data.get('date')
        
        # Validate period
        if period not in ['daily', 'weekly', 'monthly']:
            return jsonify({
                'success': False,
                'error': 'Invalid period. Must be daily, weekly, or monthly'
            }), 400
        
        # Parse date
        try:
            if date_str:
                date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
            else:
                date = datetime.now()
        except:
            date = datetime.now()
        
        # Get dashboard data
        dashboard_data = ExpenseAnalytics.get_dashboard_data(period, date)
        
        print(f"[LEGACY] ✓ Dashboard data retrieved: {period} period")
        
        return jsonify(dashboard_data), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /get_expense_dashboard: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@legacy_bp.route('/generate_expense_report', methods=['POST'])
def generate_expense_report_legacy():
    """
    LEGACY: Generate expense report (old endpoint name)
    Maps to: /api/analytics/report
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'No data provided'
            }), 400
        
        period = data.get('period', 'weekly')
        date_str = data.get('date')
        
        # Validate period
        if period not in ['daily', 'weekly', 'monthly']:
            return jsonify({
                'success': False,
                'error': 'Invalid period'
            }), 400
        
        # Parse date
        try:
            if date_str:
                date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
            else:
                date = datetime.now()
        except:
            date = datetime.now()
        
        # Generate report
        report = ReportGenerator.generate_expense_report(period, date)
        
        print(f"[LEGACY] ✓ Report generated: {period} period")
        
        return jsonify(report), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /generate_expense_report: {e}")
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@legacy_bp.route('/get_spending_alerts', methods=['GET'])
def get_spending_alerts():
    """
    LEGACY: Get AI-generated spending alerts
    """
    try:
        period = request.args.get('period', 'weekly')
        
        # Get current period dashboard
        dashboard_data = ExpenseAnalytics.get_dashboard_data(period, datetime.now())
        
        alerts = dashboard_data.get('alerts', [])
        
        print(f"[LEGACY] ✓ Retrieved {len(alerts)} alerts")
        
        return jsonify({
            'success': True,
            'alerts': alerts,
            'count': len(alerts)
        }), 200
    
    except Exception as e:
        print(f"[LEGACY ERROR] /get_spending_alerts: {e}")
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

# ============================================================================
# TEST ENDPOINTS
# ============================================================================
@legacy_bp.route('/test_bill_detection', methods=['POST'])
def test_bill_detection():
    """
    TEST ENDPOINT: Check if bill detection is working
    """
    try:
        if 'image' not in request.files:
            return jsonify({
                'success': False,
                'error': 'No image provided'
            }), 400
        
        image_file = request.files['image']
        image_bytes = image_file.read()
        
        # Decode image for info
        import cv2
        import numpy as np
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        print("="*80)
        print("[TEST] Bill Detection Test")
        print(f"[TEST] Image size: {image.shape}")
        
        # Test bill detection
        from app.services.bill_detector import detect_bill_position
        
        result = detect_bill_position(image_bytes)
        
        print(f"[TEST] Bill detected: {result.get('bill_detected')}")
        print(f"[TEST] Guidance: {result.get('guidance')}")
        print(f"[TEST] Direction: {result.get('direction')}")
        print("="*80)
        
        return jsonify({
            'success': True,
            'test_result': result,
            'image_info': {
                'width': image.shape[1],
                'height': image.shape[0],
                'channels': image.shape[2] if len(image.shape) > 2 else 1
            }
        })
    
    except Exception as e:
        print(f"[TEST ERROR] {e}")
        import traceback
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500

        
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


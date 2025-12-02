# api_enhanced.py
import cv2
import numpy as np #cv2 & numpy → image processing (for currency detection)
import traceback
from flask import Flask, request, jsonify
from datetime import datetime

# Import utilities
from config import verify_tesseract_on_startup
from ocr_utils import OCREngine
from analysis_utils import DocumentAnalyzer, SummaryGenerator, QuestionAnswerer
from currency_utils import currency_model, format_currency_name, extract_amount
from wallet_utils import (
    add_transaction, get_balance, get_total_income,
    get_total_expense, get_recent_transactions, process_question
)

# Import ENHANCED bill utilities
from enhanced_bill_utils import (
    init_enhanced_database, SmartBillExtractor, 
    save_bill_to_db, confirm_bill_and_add_transaction,
    query_expenses_natural_language, generate_weekly_summary,
    save_weekly_summary
)

# ============================================================================
# INITIALIZATION
# ============================================================================
app = Flask(__name__)

tesseract_ok = verify_tesseract_on_startup()
if not tesseract_ok:
    print("[API] Warning: Document processing may fail")

if currency_model is None:
     print("[API] Warning: Currency detection unavailable")

# Initialize Enhanced Database
init_enhanced_database()

# ============================================================================
# ENHANCED API ENDPOINTS
# ============================================================================

# --- NEW: Smart Bill Scanner ---
@app.route('/scan_bill', methods=['POST'])
def scan_bill():
    """Scan bill, extract info, and prepare for confirmation"""
    if not tesseract_ok:
        return jsonify({'error': 'OCR not available'}), 500
    if 'image' not in request.files:
        return jsonify({'error': 'No image file'}), 400
    
    print("\n[API /scan_bill] Processing bill...")
    try:
        file = request.files['image']
        img_bytes = file.read()
        
        # Extract text using OCR
        full_text = OCREngine.extract_text(img_bytes)
        if not full_text or not full_text.strip():
            return jsonify({'error': 'Could not extract text from bill'}), 500
        
        print(f"[API] Extracted {len(full_text)} characters")
        
        # Extract fields
        fields = DocumentAnalyzer.extract_fields(full_text)
        
        # Extract bill information
        bill_info = SmartBillExtractor.extract_bill_info(full_text, fields)
        
        if bill_info['total_amount'] <= 0:
            return jsonify({'error': 'Could not detect bill amount'}), 400
        
        # Save bill to database (unconfirmed)
        bill_id = save_bill_to_db(bill_info)
        
        if not bill_id:
            return jsonify({'error': 'Failed to save bill'}), 500
        
        # Generate confirmation message
        confirmation_msg = SmartBillExtractor.generate_confirmation_message(bill_info)
        
        print(f"[API] ✓ Bill scanned: {bill_info['vendor']} - Rs.{bill_info['total_amount']}")
        
        return jsonify({
            'bill_id': bill_id,
            'bill_info': bill_info,
            'confirmation_message': confirmation_msg,
            'full_text': full_text,
        })
        
    except Exception as e:
        print(f"[API ERROR] /scan_bill failed: {e}")
        traceback.print_exc()
        return jsonify({'error': f'Internal error: {str(e)}'}), 500

# Add this to api_enhanced.py - Replace the /scan_bill_display_only endpoint

@app.route('/scan_bill_display_only', methods=['POST'])
def scan_bill_display_only():
    """Scan bill using YOLO ONLY - Fast and accurate"""
    if 'image' not in request.files:
        return jsonify({'error': 'No image file', 'success': False}), 400
    
    print("\n[API /scan_bill_display_only] Processing with YOLO-only...")
    try:
        file = request.files['image']
        img_bytes = file.read()
        
        print(f"[API] Image size: {len(img_bytes)} bytes")
        
        # Validate image
        if len(img_bytes) < 1000:
            return jsonify({
                'error': 'Image too small or corrupted',
                'success': False
            }), 400
        
        # ⭐ STEP 1: Extract fields using YOLO (PRIMARY METHOD)
        print("[API] Step 1: YOLO field extraction...")
        yolo_fields = {}
        try:
            from receipt_field_extractor import extract_receipt_fields
            yolo_result = extract_receipt_fields(img_bytes)
            
            if yolo_result.get('success'):
                yolo_fields = {
                    'company': yolo_result.get('company', ''),
                    'date': yolo_result.get('date', ''),
                    'address': yolo_result.get('address', ''),
                    'total': yolo_result.get('total', '')
                }
                print(f"[API] YOLO extracted:")
                print(f"  Company: {yolo_fields.get('company', 'N/A')}")
                print(f"  Date: {yolo_fields.get('date', 'N/A')}")
                print(f"  Address: {yolo_fields.get('address', 'N/A')}")
                print(f"  Total: {yolo_fields.get('total', 'N/A')}")
            else:
                print("[API] ⚠ YOLO extraction failed")
        except Exception as e:
            print(f"[API] YOLO error: {e}")
            import traceback
            traceback.print_exc()
        
        # ⭐ STEP 2: Process YOLO results (no OCR needed for items)
        print("[API] Step 2: Processing YOLO results...")
        
        # For category detection, we need vendor name - get from YOLO or use empty
        vendor_for_category = yolo_fields.get('company', 'Unknown')
        
        # Build bill_info directly from YOLO
        from smart_category_detector import get_category, get_category_icon
        
        total_amount = 0.0
        if yolo_fields.get('total'):
            try:
                import re
                amount_str = re.sub(r'[^\d.]', '', yolo_fields['total'])
                if amount_str:
                    total_amount = float(amount_str)
            except:
                pass
        
        category = get_category(vendor_for_category, [], '')  # No items needed
        
        bill_info = {
            'vendor': yolo_fields.get('company', 'Unknown'),
            'address': yolo_fields.get('address', ''),
            'date': yolo_fields.get('date', ''),
            'total_amount': total_amount,
            'category': category,
            'items': [],  # No items - YOLO doesn't detect items
            'scanned_at': datetime.now().isoformat()
        }
        
        # Validation: At least vendor OR amount must be present
        has_vendor = bill_info['vendor'] and bill_info['vendor'] != 'Unknown'
        has_amount = bill_info['total_amount'] > 0
        
        if not has_vendor and not has_amount:
            print("[API] ✗ No vendor or amount detected")
            return jsonify({
                'error': 'Could not extract vendor or amount. Please ensure bill is clearly visible.',
                'success': False,
                'debug': {
                    'yolo_fields': yolo_fields
                }
            }), 400
        
        # Generate message for voice
        message_parts = []
        
        if bill_info['vendor'] and bill_info['vendor'] != 'Unknown':
            message_parts.append(bill_info['vendor'])
        
        if bill_info['total_amount'] > 0:
            message_parts.append(f"Total amount: {bill_info['total_amount']} rupees")
        
        if bill_info['category'] and bill_info['category'] != 'General':
            message_parts.append(f"Category: {bill_info['category']}")
        
        if bill_info['date']:
            message_parts.append(f"Date: {bill_info['date']}")
        
        if bill_info.get('address'):
            message_parts.append(f"Address: {bill_info['address']}")
        
        message = ". ".join(message_parts)
        
        print(f"[API] ✓ Bill info extracted:")
        print(f"  Vendor: {bill_info['vendor']}")
        print(f"  Address: {bill_info.get('address', 'N/A')}")
        print(f"  Date: {bill_info['date']}")
        print(f"  Amount: Rs.{bill_info['total_amount']}")
        print(f"  Category: {bill_info['category']}")
        
        return jsonify({
            'success': True,
            'bill_info': bill_info,
            'message': message,
            'extraction_method': 'YOLO-only',
            'debug': {
                'yolo_success': bool(yolo_fields),
                'yolo_fields': yolo_fields
            }
        })
        
    except Exception as e:
        error_msg = str(e)
        print(f"[API ERROR] /scan_bill_display_only failed: {error_msg}")
        traceback.print_exc()
        
        return jsonify({
            'error': 'Could not process bill. Please try again.',
            'success': False,
            'debug': {
                'error_type': type(e).__name__,
                'error_detail': error_msg[:200]
            }
        }), 500

@app.route('/detect_currency_ar', methods=['POST'])
def detect_currency_ar():
    """
    Enhanced currency detection with AR overlay data
    Returns bounding boxes and positions for AR visualization
    """
    if currency_model is None: 
        return jsonify({'error': 'Currency model not loaded'}), 500
    if 'image' not in request.files: 
        return jsonify({'error': 'No image file'}), 400

    try:
        file = request.files['image']
        img_bytes = file.read()
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if frame is None:
            return jsonify({'error': 'Invalid image'}), 400
        
        height, width = frame.shape[:2]
        print(f"\n[API /detect_currency_ar] Image size: {width}x{height}")

        # Run YOLO detection
        results = currency_model(frame, conf=0.5)
        detections = []

        if results and len(results) > 0:
            result = results[0]
            
            if hasattr(result, 'boxes') and result.boxes is not None:
                boxes = result.boxes
                
                for i, box in enumerate(boxes):
                    # Get bounding box coordinates (normalized 0-1)
                    xyxy = box.xyxy[0].cpu().numpy()  # [x1, y1, x2, y2]
                    x1, y1, x2, y2 = xyxy
                    
                    # Normalize coordinates
                    x1_norm = float(x1 / width)
                    y1_norm = float(y1 / height)
                    x2_norm = float(x2 / width)
                    y2_norm = float(y2 / height)
                    
                    # Calculate center
                    center_x = (x1_norm + x2_norm) / 2
                    center_y = (y1_norm + y2_norm) / 2
                    
                    # Get class and confidence
                    cls_idx = int(box.cls[0].cpu().numpy())
                    confidence = float(box.conf[0].cpu().numpy())
                    label = result.names[cls_idx]
                    
                    # Extract amount
                    amount = extract_amount(label)
                    
                    if amount is not None:
                        detection = {
                            'label': label,
                            'amount': int(amount),
                            'confidence': confidence,
                            'x1': x1_norm,
                            'y1': y1_norm,
                            'x2': x2_norm,
                            'y2': y2_norm,
                            'center_x': center_x,
                            'center_y': center_y,
                            'width': x2_norm - x1_norm,
                            'height': y2_norm - y1_norm,
                        }
                        detections.append(detection)
                        print(f"  ✓ Detected: Rs.{amount} at ({center_x:.2f}, {center_y:.2f})")
        
        print(f"[API] Total detections: {len(detections)}")
        
        return jsonify({
            'success': True,
            'count': len(detections),
            'detections': detections,
            'image_size': {'width': width, 'height': height}
        })

    except Exception as e:
        print(f"[API ERROR] /detect_currency_ar: {e}")
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500
    


    
# --- NEW: Confirm Bill ---
@app.route('/confirm_bill', methods=['POST'])
def confirm_bill():
    """Confirm scanned bill and add to expenses"""
    data = request.json
    
    if not data or 'bill_id' not in data:
        return jsonify({'error': 'Missing bill_id'}), 400
    
    print(f"\n[API /confirm_bill] Confirming bill {data['bill_id']}...")
    
    try:
        bill_id = int(data['bill_id'])
        success, message = confirm_bill_and_add_transaction(bill_id)
        
        if success:
            new_balance = get_balance()
            print(f"[API] ✓ Bill confirmed. New balance: Rs.{new_balance}")
            return jsonify({
                'success': True,
                'message': message,
                'new_balance': new_balance,
            })
        else:
            return jsonify({'error': message}), 400
            
    except Exception as e:
        print(f"[API ERROR] /confirm_bill failed: {e}")
        traceback.print_exc()
        return jsonify({'error': f'Internal error: {str(e)}'}), 500

# --- NEW: Query Expenses (Natural Language) ---
@app.route('/query_expenses', methods=['POST'])
def query_expenses():
    """Handle natural language expense queries"""
    data = request.json
    
    if not data or 'query' not in data:
        return jsonify({'error': 'Missing query'}), 400
    
    print(f"\n[API /query_expenses] Query: {data['query']}")
    
    try:
        query = data['query']
        answer = query_expenses_natural_language(query)
        
        print(f"[API] ✓ Answer: {answer}")
        return jsonify({'answer': answer})
        
    except Exception as e:
        print(f"[API ERROR] /query_expenses failed: {e}")
        traceback.print_exc()
        return jsonify({'error': f'Internal error: {str(e)}'}), 500

# --- NEW: Generate Weekly Summary ---
@app.route('/weekly_summary', methods=['GET'])
def weekly_summary():
    """Generate and return weekly spending summary"""
    print("\n[API /weekly_summary] Generating summary...")
    
    try:
        summary = generate_weekly_summary()
        
        # Optionally save to database
        save_weekly_summary(summary)
        
        print(f"[API] ✓ Summary: Rs.{summary['total_spending']}")
        return jsonify(summary)
        
    except Exception as e:
        print(f"[API ERROR] /weekly_summary failed: {e}")
        traceback.print_exc()
        return jsonify({'error': f'Internal error: {str(e)}'}), 500

# --- EXISTING: Currency Detector ---
@app.route('/detect_currency', methods=['POST'])
def detect_currency():
    if currency_model is None: 
        return jsonify({'error': 'Currency model not loaded'}), 500
    if 'image' not in request.files: 
        return jsonify({'error': 'No image file'}), 400

    try:
        file = request.files['image']
        img_bytes = file.read()
        nparr = np.frombuffer(img_bytes, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        print("\n[API /detect_currency] Analyzing...")
        results = currency_model(frame, conf=0.5)
        detected_items = []
        message = "No currency detected"

        if results:
            if hasattr(results[0], 'names') and hasattr(results[0], 'boxes') and hasattr(results[0].boxes, 'cls'):
                class_indices = results[0].boxes.cls.cpu().numpy()
                labels = [results[0].names[int(cls_idx)] for cls_idx in class_indices]
                
                for label in labels:
                    amount = extract_amount(label)
                    if amount is not None:
                        formatted_name = format_currency_name(label)
                        detected_items.append({
                            'label': label, 
                            'name': formatted_name, 
                            'amount': amount
                        })
                        print(f"✓ Currency: {formatted_name} ({amount})")
                
                if detected_items:
                    if len(detected_items) == 1:
                        message = f"This is {detected_items[0]['name']}"
                    else:
                        currencies = [item['name'] for item in detected_items]
                        currency_list = ", ".join(currencies[:-1]) + f" and {currencies[-1]}"
                        message = f"I detected {currency_list}"

        return jsonify({'message': message, 'detected_items': detected_items})

    except Exception as e:
        print(f"[API ERROR] /detect_currency: {e}")
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

# --- EXISTING: Wallet Endpoints ---
@app.route('/add_wallet_transaction', methods=['POST'])
def add_wallet_transaction_route():
    data = request.json
    if not data or not all(k in data for k in ['amount', 'type', 'category']):
        return jsonify({'error': 'Missing required fields'}), 400

    try:
        amount = float(data['amount'])
        trans_type = data['type'].lower()
        category = data['category']
        description = data.get('description', '')

        if trans_type not in ['income', 'expense']:
            return jsonify({'error': 'Invalid type'}), 400
        if amount <= 0:
             return jsonify({'error': 'Amount must be positive'}), 400

        success = add_transaction(amount, trans_type, category, description)
        if success:
            return jsonify({
                'message': 'Transaction added',
                'new_balance': get_balance()
            })
        return jsonify({'error': 'Failed to add transaction'}), 500

    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/ask_wallet_question', methods=['POST'])
def ask_wallet_question_route():
    data = request.json
    if not data or 'question' not in data:
        return jsonify({'error': 'Missing question'}), 400

    try:
        answer = process_question(data['question'])
        return jsonify({'answer': answer})
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/get_wallet_balance', methods=['GET'])
def get_wallet_balance_route():
    try:
        return jsonify({'balance': get_balance()})
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/get_recent_transactions', methods=['GET'])
def get_recent_transactions_route():
    limit = request.args.get('limit', 5, type=int)
    try:
        return jsonify({'transactions': get_recent_transactions(limit)})
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

# --- EXISTING: Document Processing ---
@app.route('/process_document', methods=['POST'])
def process_document():
    if not tesseract_ok or 'image' not in request.files:
        return jsonify({'error': 'OCR unavailable or no image'}), 400
    
    try:
        file = request.files['image']
        full_text = OCREngine.extract_text(file.read())
        
        if not full_text.strip():
            return jsonify({'error': 'No text extracted'}), 500
        
        doc_type = DocumentAnalyzer.detect_document_type(full_text)
        fields = DocumentAnalyzer.extract_fields(full_text)
        summary = SummaryGenerator.generate_summary(fields, doc_type)
        
        return jsonify({
            'full_text': full_text,
            'doc_type': doc_type,
            'fields': fields,
            'summary': summary
        })
        
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/ask_question', methods=['POST'])
def ask_question():
    data = request.json
    if not data or not all(k in data for k in ['question', 'fields', 'full_text']):
        return jsonify({'error': 'Missing data'}), 400
    
    try:
        qa = QuestionAnswerer(data['fields'], data['full_text'])
        return jsonify({'answer': qa.answer(data['question'])})
    except Exception as e:
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

# ============================================================================
# RUN SERVER
# ============================================================================
if __name__ == "__main__":
    print("=" * 70)
    print(" 🚀 ENHANCED SMART ASSISTANT API")
    print("=" * 70)
    print(f" ✓ Bill Scanner: Ready")
    print(f" ✓ Expense Tracker: Ready")
    print(f" ✓ Weekly Summaries: Ready")
    print(f" {'✓' if tesseract_ok else '✗'} OCR: {'Ready' if tesseract_ok else 'Not Available'}")
    print(f" {'✓' if currency_model else '✗'} Currency: {'Ready' if currency_model else 'Not Available'}")
    print("=" * 70)
    app.run(host='0.0.0.0', port=5000, debug=True)
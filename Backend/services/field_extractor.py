# FILE: app/services/field_extractor.py
# YOLO-based field extraction from receipts
# ============================================================================

"""
Field Extraction Service
Extract structured fields from receipts using YOLO + OCR
"""

import cv2
import numpy as np
from ultralytics import YOLO
import easyocr
import re
import os
from typing import Dict, List
from app.config.settings import OLD_YOLO_MODEL_PATH, NEW_YOLO_MODEL_PATH

# ============================================================================
# MODEL INITIALIZATION
# ============================================================================

old_model = None
new_model = None
reader = None

def init_models():
    """Initialize YOLO models and EasyOCR"""
    global old_model, new_model, reader
    
    print("[FIELD EXTRACTOR] Initializing models...")
    
    # Load old model (for company, date, address)
    if os.path.exists(OLD_YOLO_MODEL_PATH):
        try:
            old_model = YOLO(OLD_YOLO_MODEL_PATH)
            print("  ✓ OLD model loaded")
        except Exception as e:
            print(f"  ✗ OLD model failed: {e}")
    else:
        print(f"  ⚠️  OLD model not found: {OLD_YOLO_MODEL_PATH}")
    
    # Load new model (for total, cash, change)
    if os.path.exists(NEW_YOLO_MODEL_PATH):
        try:
            new_model = YOLO(NEW_YOLO_MODEL_PATH)
            print("  ✓ NEW model loaded")
        except Exception as e:
            print(f"  ✗ NEW model failed: {e}")
    else:
        print(f"  ⚠️  NEW model not found: {NEW_YOLO_MODEL_PATH}")
    
    # Initialize EasyOCR
    try:
        reader = easyocr.Reader(['en'], gpu=False, verbose=False)
        print("  ✓ EasyOCR ready")
    except Exception as e:
        print(f"  ✗ EasyOCR failed: {e}")

# Initialize on import
init_models()

# ============================================================================
# FIELD EXTRACTION
# ============================================================================

def extract_receipt_fields(image_bytes: bytes) -> Dict:
    """
    Extract receipt fields using dual YOLO models + OCR
    
    Args:
        image_bytes: Raw image bytes
    
    Returns:
        Dict with success, company, date, address, total, cash, change
    """
    try:
        # Decode image
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return _error_response("Invalid image")
        
        print(f"[FIELD EXTRACTOR] Processing image: {image.shape[1]}x{image.shape[0]}")
        
        # Quick enhancement
        enhanced = _quick_enhance(image)
        
        # Detect with OLD model (company, date, address)
        old_detections = _detect_with_model(
            old_model, enhanced, ['company', 'date', 'address'], "OLD"
        )
        
        # Detect with NEW model (total, cash, change)
        new_detections = _detect_with_model(
            new_model, enhanced, ['total', 'cash', 'change'], "NEW"
        )
        
        # Merge detections
        all_detections = {**old_detections, **new_detections}
        
        # Extract text with OCR
        extracted = {}
        for field in ['company', 'date', 'address', 'total', 'cash', 'change']:
            if field in all_detections:
                text = _extract_text_from_bbox(
                    enhanced, all_detections[field]['bbox'], field
                )
                if text:
                    extracted[field] = text
        
        # Use cash as fallback for total if total is missing
        if not extracted.get('total') and extracted.get('cash'):
            extracted['total'] = extracted['cash']
            print("[FIELD EXTRACTOR] Using cash as total (fallback)")
        
        print(f"[FIELD EXTRACTOR] ✓ Extracted {len(extracted)} fields")
        
        return {
            'success': True,
            'company': extracted.get('company', ''),
            'date': extracted.get('date', ''),
            'address': extracted.get('address', ''),
            'total': extracted.get('total', ''),
            'cash': extracted.get('cash', ''),
            'change': extracted.get('change', '')
        }
    
    except Exception as e:
        print(f"[FIELD EXTRACTOR ERROR] {e}")
        import traceback
        traceback.print_exc()
        return _error_response(str(e))

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _error_response(error_msg: str) -> Dict:
    """Create error response"""
    return {
        'success': False,
        'error': error_msg,
        'company': '',
        'date': '',
        'address': '',
        'total': '',
        'cash': '',
        'change': ''
    }

def _quick_enhance(image: np.ndarray) -> np.ndarray:
    """Quick CLAHE enhancement"""
    try:
        lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        l = clahe.apply(l)
        return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)
    except:
        return image

def _detect_with_model(model, image: np.ndarray, fields: List[str], 
                       model_name: str) -> Dict:
    """Run YOLO detection"""
    if model is None:
        print(f"  [{model_name}] Model not available")
        return {}
    
    detections = {}
    
    try:
        results = model(image, conf=0.15, verbose=False, imgsz=640, half=False)
        
        for result in results:
            boxes = result.boxes
            if boxes is None:
                continue
            
            for i in range(len(boxes)):
                box = boxes.xyxy[i].cpu().numpy()
                conf = float(boxes.conf[i].cpu().numpy())
                cls = int(boxes.cls[i].cpu().numpy())
                
                class_name = model.names[cls]
                field = _normalize_class(class_name)
                
                if field in fields:
                    if field not in detections or conf > detections[field]['conf']:
                        detections[field] = {
                            'bbox': box.tolist(),
                            'conf': conf
                        }
        
        print(f"  [{model_name}] Found: {list(detections.keys())}")
        
    except Exception as e:
        print(f"  [{model_name}] Error: {e}")
    
    return detections

def _normalize_class(name: str) -> str:
    """Map YOLO class name to field name"""
    name = name.lower()
    
    if 'company' in name or 'vendor' in name or 'name' in name:
        return 'company'
    elif 'date' in name:
        return 'date'
    elif 'address' in name:
        return 'address'
    elif 'total_price' in name or 'total.total_price' in name:
        return 'total'
    elif 'cash_price' in name or 'total.cash_price' in name:
        return 'cash'
    elif 'change_price' in name or 'total.change_price' in name:
        return 'change'
    
    return name

def _extract_text_from_bbox(image: np.ndarray, bbox: List[float], 
                            field: str) -> str:
    """Extract text from bounding box using EasyOCR"""
    if reader is None:
        return ""
    
    try:
        x1, y1, x2, y2 = map(int, bbox)
        
        # Add padding
        pad = 10 if field in ['total', 'cash', 'change'] else 5
        x1 = max(0, x1 - pad)
        y1 = max(0, y1 - pad)
        x2 = min(image.shape[1], x2 + pad)
        y2 = min(image.shape[0], y2 + pad)
        
        # Extract ROI
        roi = image[y1:y2, x1:x2]
        if roi.size == 0:
            return ""
        
        # OCR
        results = reader.readtext(roi, detail=0)
        if results:
            text = ' '.join(results)
            cleaned = _clean_field_text(text, field)
            return cleaned
        
        return ""
        
    except Exception as e:
        print(f"[OCR ERROR] Field {field}: {e}")
        return ""

def _clean_field_text(text: str, field: str) -> str:
    """Clean extracted text based on field type"""
    if not text:
        return ""
    
    text = text.strip()
    
    if field == 'company':
        # Remove if mostly numbers or too short
        if len(text) < 2 or re.match(r'^[\d\s\-:\.]+$', text):
            return ""
        return text[:100]
    
    elif field in ['total', 'cash', 'change']:
        # Extract numbers only
        nums = re.findall(r'\d+\.?\d*', re.sub(r'[^0-9\.]', ' ', text))
        if nums:
            try:
                amounts = [float(n) for n in nums if 0 < float(n) < 100000]
                if amounts:
                    val = max(amounts) if field == 'total' else amounts[0]
                    return f"{val:.2f}"
            except:
                pass
        return ""
    
    elif field == 'date':
        # Try to find date pattern
        match = re.search(r'\d{1,2}[/-]\d{1,2}[/-]?\d{0,4}', text)
        if match:
            return match.group(0)
        if re.search(r'\d', text) and len(text) < 20:
            return text
        return ""
    
    elif field == 'address':
        return text[:150] if len(text) > 2 else ""
    
    return text[:100]

# ============================================================================
# FILE: app/services/field_extractor.py (IMPROVED FOR ACCURACY)
# Enhanced extraction for visually impaired users
# ============================================================================

import cv2
import numpy as np
from ultralytics import YOLO
from typing import Dict, List, Tuple
import re
from pathlib import Path
from config import Config
from app.services.paddle_ocr_service import get_ocr_service

class FieldExtractor:
    """High-accuracy field extraction for visually impaired users"""
    
    def __init__(self):
        """Initialize with enhanced settings"""
        # OCR Service
        self.ocr = get_ocr_service()
        print(f"[FIELD EXTRACTOR] Using OCR: {self.ocr.get_engine_name()}")
        
        # YOLO Models
        self.old_model = None
        self.new_model = None
        self._load_models()
        
        self.old_classes = ["company", "address", "date"]
        self.new_classes = [
            "menu.cnt", "menu.nm", "menu.price",
            "total.total_price", "total.cashprice", "total.changeprice"
        ]
        
        # Enhanced filtering thresholds
        self.MIN_CONFIDENCE = 0.15  # Lower to catch more detections
        self.MIN_ITEM_NAME_LENGTH = 2
        self.MIN_PRICE = 0.50
        self.MAX_PRICE = 10000.00
        self.MAX_QUANTITY = 50
    
    def _load_models(self):
        """Load YOLO models"""
        if Path(Config.OLD_YOLO_MODEL_PATH).exists():
            try:
                self.old_model = YOLO(Config.OLD_YOLO_MODEL_PATH)
                print(f"[FIELD EXTRACTOR] ✓ Old model loaded")
            except Exception as e:
                print(f"[FIELD EXTRACTOR] ✗ Old model failed: {e}")
        
        possible_paths = [
            Config.NEW_YOLO_MODEL_PATH, 
            "runs/train/cord_improved/weights/best.pt",
            "models/best.pt"
        ]
        for path in possible_paths:
            if Path(path).exists():
                try:
                    self.new_model = YOLO(path)
                    print(f"[FIELD EXTRACTOR] ✓ New model loaded from {path}")
                    break
                except Exception as e:
                    print(f"[FIELD EXTRACTOR] Failed to load {path}: {e}")
    
    def extract_all_fields(self, image_bytes: bytes) -> Dict:
        """Extract all fields with maximum accuracy"""
        print("\n" + "="*80)
        print("[EXTRACTION] Starting HIGH-ACCURACY extraction...")
        
        # Decode image
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return {'success': False, 'error': 'Failed to decode image'}
        
        height, width = image.shape[:2]
        print(f"[IMAGE] Original size: {width}x{height}")
        
        # Don't downscale - keep original for best OCR
        # Apply slight denoising only
        image = cv2.fastNlMeansDenoisingColored(image, None, 10, 10, 7, 21)
        
        result = {
            'success': True,
            'company': '',
            'address': '',
            'date': '',
            'menu_items': [],
            'total': '',
            'cash': '',
            'change': '',
        }
        
        # Extract basic info with multiple attempts
        if self.old_model:
            old_results = self._extract_basic_info_robust(image)
            result.update(old_results)
            print(f"[BASIC INFO] Company: '{result['company']}'")
            print(f"[BASIC INFO] Address: '{result['address']}'")
            print(f"[BASIC INFO] Date: '{result['date']}'")
        
        # Extract menu items with enhanced accuracy
        if self.new_model:
            print("\n[MENU EXTRACTION] Starting...")
            new_results = self._extract_menu_robust(image)
            result['menu_items'] = new_results.get('menu_items', [])
            result['total'] = new_results.get('total', '')
            result['cash'] = new_results.get('cash', '')
            result['change'] = new_results.get('change', '')
            
            print(f"[MENU EXTRACTION] ✓ Found {len(result['menu_items'])} items")
            for i, item in enumerate(result['menu_items']):
                print(f"  [{i+1}] {item['name']} - Rs.{item['price']} x{item['count']}")
            print(f"[TOTALS] Total: Rs.{result['total']}, Cash: Rs.{result['cash']}, Change: Rs.{result['change']}")
        
        print("="*80 + "\n")
        return result
    
    def _extract_basic_info_robust(self, image: np.ndarray) -> Dict:
        """Extract company, address, date with multiple strategies"""
        extracted = {'company': '', 'address': '', 'date': ''}
        
        try:
            # Strategy 1: YOLO detection with low confidence
            results = self.old_model.predict(
                source=image,
                imgsz=640,
                conf=0.10,  # Very low to catch everything
                iou=0.3,
                verbose=False
            )
            
            if results and results[0].boxes and len(results[0].boxes) > 0:
                extracted = self._process_basic_detections(image, results[0].boxes)
            
            # Strategy 2: If company still empty, OCR top region
            if not extracted['company']:
                print("[FALLBACK] Trying full OCR of top region...")
                height = image.shape[0]
                top_region = image[0:int(height * 0.35), :]
                
                full_text = self.ocr.extract_text_from_roi(top_region, 'company')
                if full_text:
                    lines = [l.strip() for l in full_text.split('\n') if l.strip()]
                    if lines:
                        extracted['company'] = self._clean_company(lines[0])
                        print(f"[FALLBACK] Extracted company: '{extracted['company']}'")
                        
                        # Try to find address and date in remaining lines
                        for line in lines[1:]:
                            if not extracted['date'] and self._looks_like_date(line):
                                extracted['date'] = self._clean_date(line)
                            elif not extracted['address'] and len(line) > 10:
                                extracted['address'] = self._clean_address(line)
            
            return extracted
            
        except Exception as e:
            print(f"[BASIC INFO ERROR] {e}")
            import traceback
            traceback.print_exc()
            return extracted
    
    def _process_basic_detections(self, image: np.ndarray, boxes) -> Dict:
        """Process YOLO detections for basic info"""
        extracted = {'company': '', 'address': '', 'date': ''}
        
        company_candidates = []
        address_candidates = []
        date_candidates = []
        
        for box in boxes:
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            
            if cls_id >= len(self.old_classes):
                continue
            
            class_name = self.old_classes[cls_id]
            roi = image[y1:y2, x1:x2]
            
            if roi.size == 0:
                continue
            
            # Extract text with OCR
            text = self.ocr.extract_text_from_roi(roi, class_name)
            
            if not text or len(text) < 2:
                continue
            
            # Store candidates
            if class_name == 'company':
                cleaned = self._clean_company(text)
                if self._is_valid_company(cleaned):
                    company_candidates.append({
                        'text': cleaned,
                        'conf': conf,
                        'y': y1,
                        'length': len(cleaned)
                    })
            
            elif class_name == 'address':
                cleaned = self._clean_address(text)
                if len(cleaned) >= 5:
                    address_candidates.append({
                        'text': cleaned,
                        'conf': conf,
                        'length': len(cleaned)
                    })
            
            elif class_name == 'date':
                cleaned = self._clean_date(text)
                if self._is_valid_date(cleaned):
                    date_candidates.append({
                        'text': cleaned,
                        'conf': conf
                    })
        
        # Select best candidates
        if company_candidates:
            # Prefer: high confidence, topmost position, reasonable length
            company_candidates.sort(key=lambda x: (x['conf'] * 0.6, -x['y'], x['length']), reverse=True)
            extracted['company'] = company_candidates[0]['text']
        
        if address_candidates:
            # Prefer longest address with decent confidence
            address_candidates.sort(key=lambda x: (x['length'], x['conf']), reverse=True)
            extracted['address'] = address_candidates[0]['text']
        
        if date_candidates:
            # Prefer highest confidence
            date_candidates.sort(key=lambda x: x['conf'], reverse=True)
            extracted['date'] = date_candidates[0]['text']
        
        return extracted
    
    def _extract_menu_robust(self, image: np.ndarray) -> Dict:
        """Extract menu items with enhanced accuracy"""
        try:
            # Run YOLO with optimized settings
            results = self.new_model.predict(
                source=image,
                imgsz=1280,  # Higher resolution for better detection
                conf=self.MIN_CONFIDENCE,
                iou=0.5,
                verbose=False
            )
            
            if not results or len(results) == 0 or not results[0].boxes:
                print("[MENU] No detections found")
                return {'menu_items': [], 'total': '', 'cash': '', 'change': ''}
            
            boxes = results[0].boxes
            print(f"[MENU] Found {len(boxes)} raw detections")
            
            # Collect all detections
            detections = []
            totals = {'total': '', 'cash': '', 'change': ''}
            
            for idx, box in enumerate(boxes):
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                cls_id = int(box.cls[0])
                conf = float(box.conf[0])
                
                if cls_id >= len(self.new_classes):
                    continue
                
                class_name = self.new_classes[cls_id]
                roi = image[y1:y2, x1:x2]
                
                if roi.size == 0:
                    continue
                
                # Extract text
                text = self.ocr.extract_text_from_roi(roi, class_name)
                
                detection = {
                    'index': idx,
                    'class': class_name,
                    'bbox': (x1, y1, x2, y2),
                    'confidence': conf,
                    'text': text,
                    'center_y': (y1 + y2) // 2,
                    'center_x': (x1 + x2) // 2,
                    'y1': y1,
                    'y2': y2,
                    'x1': x1,
                    'x2': x2
                }
                
                # Handle totals
                if class_name == 'total.total_price':
                    cleaned = self._clean_number(text)
                    if cleaned and self._is_valid_price(cleaned):
                        if not totals['total'] or float(cleaned) > float(totals['total'] or 0):
                            totals['total'] = cleaned
                
                elif class_name == 'total.cashprice':
                    cleaned = self._clean_number(text)
                    if cleaned:
                        totals['cash'] = cleaned
                
                elif class_name == 'total.changeprice':
                    cleaned = self._clean_number(text)
                    if cleaned:
                        totals['change'] = cleaned
                
                detections.append(detection)
                print(f"  [{idx}] {class_name}: '{text}' @ y={y1}-{y2}, conf={conf:.2f}")
            
            # Group menu items
            menu_items = self._group_menu_items_enhanced(detections, image.shape[0])
            
            return {
                'menu_items': menu_items,
                'total': totals['total'],
                'cash': totals['cash'],
                'change': totals['change']
            }
            
        except Exception as e:
            print(f"[MENU ERROR] {e}")
            import traceback
            traceback.print_exc()
            return {'menu_items': [], 'total': '', 'cash': '', 'change': ''}
    
    def _group_menu_items_enhanced(self, detections: List[Dict], image_height: int) -> List[Dict]:
        """Enhanced grouping with better validation"""
        # Filter menu-only detections
        menu_dets = [d for d in detections if d['class'].startswith('menu.')]
        
        if not menu_dets:
            print("[GROUPING] No menu detections found")
            return []
        
        # Skip header region (top 20%)
        min_y = image_height * 0.20
        menu_dets = [d for d in menu_dets if d['y1'] > min_y]
        print(f"[GROUPING] After header filter: {len(menu_dets)} detections")
        
        # Sort by vertical position
        menu_dets.sort(key=lambda x: x['center_y'])
        
        # Group into rows (items on same horizontal line)
        rows = []
        current_row = []
        row_threshold = 35  # pixels
        
        for det in menu_dets:
            if not current_row:
                current_row = [det]
            elif abs(det['center_y'] - current_row[0]['center_y']) <= row_threshold:
                current_row.append(det)
            else:
                rows.append(current_row)
                current_row = [det]
        
        if current_row:
            rows.append(current_row)
        
        print(f"[GROUPING] Formed {len(rows)} rows")
        
        # Build menu items
        menu_items = []
        
        # Words to skip (common non-item text)
        skip_patterns = [
            r'^(CITY|SPRING|BLVD|PHONE|Ph:|ORDER|ATM|TABLE|WELCOME|and|RESTAURANT|MIAMI|BEACH)$',
            r'^[#@$%&*]+$',
            r'^(TOTAL|SUBTOTAL|TAX|DISCOUNT)$'
        ]
        
        for row_idx, row in enumerate(rows):
            # Sort row by X position (left to right)
            row.sort(key=lambda x: x['center_x'])
            
            item = {
                'name': '',
                'price': '',
                'count': '1',
                'price_numeric': 0.0,
                'count_numeric': 1
            }
            
            name_parts = []
            
            for det in row:
                text = det['text'].strip()
                
                if det['class'] == 'menu.nm':
                    # Skip if matches skip patterns
                    if any(re.match(pattern, text, re.IGNORECASE) for pattern in skip_patterns):
                        continue
                    
                    # Valid name part
                    if len(text) >= self.MIN_ITEM_NAME_LENGTH and re.search(r'[a-zA-Z]', text):
                        name_parts.append(text)
                
                elif det['class'] == 'menu.price':
                    cleaned = self._clean_number(text)
                    if cleaned and self._is_valid_price(cleaned):
                        price_val = float(cleaned)
                        # Take highest price in row (likely the item price)
                        if price_val > item['price_numeric']:
                            item['price'] = cleaned
                            item['price_numeric'] = price_val
                
                elif det['class'] == 'menu.cnt':
                    cleaned = self._clean_number(text)
                    if cleaned:
                        try:
                            count_val = int(float(cleaned))
                            if 1 <= count_val <= self.MAX_QUANTITY:
                                item['count'] = str(count_val)
                                item['count_numeric'] = count_val
                        except:
                            pass
            
            # Combine name parts
            if name_parts:
                item['name'] = ' '.join(name_parts)
            
            # Only add if has name AND price
            if item['name'] and item['price_numeric'] >= self.MIN_PRICE:
                menu_items.append(item)
                print(f"  Row {row_idx+1}: ✓ '{item['name']}' - Rs.{item['price']} x{item['count']}")
            else:
                print(f"  Row {row_idx+1}: ✗ Skipped - name='{item['name']}', price={item['price_numeric']}")
        
        return menu_items
    
    # Validation helpers
    def _is_valid_company(self, text: str) -> bool:
        return len(text) >= 2 and re.search(r'[a-zA-Z]', text)
    
    def _is_valid_date(self, text: str) -> bool:
        patterns = [
            r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}',
            r'\d{4}[-/]\d{1,2}[-/]\d{1,2}',
            r'\d{1,2}\s+[A-Za-z]{3,}\s+\d{2,4}'
        ]
        return any(re.search(p, text) for p in patterns)
    
    def _looks_like_date(self, text: str) -> bool:
        return bool(re.search(r'\d{1,2}[-/]\d{1,2}', text))
    
    def _is_valid_price(self, price_str: str) -> bool:
        try:
            val = float(price_str)
            return self.MIN_PRICE <= val <= self.MAX_PRICE
        except:
            return False
    
    # Cleaning helpers
    def _clean_company(self, text: str) -> str:
        text = ' '.join(text.split())
        text = re.sub(r'[^a-zA-Z0-9\s\-&.,()\'"]', '', text)
        return text.strip('.,;:"\'-')
    
    def _clean_address(self, text: str) -> str:
        return ' '.join(text.split())
    
    def _clean_date(self, text: str) -> str:
        patterns = [
            r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}',
            r'\d{4}[-/]\d{1,2}[-/]\d{1,2}',
            r'\d{1,2}\s+[A-Za-z]{3,}\s+\d{2,4}'
        ]
        for pattern in patterns:
            match = re.search(pattern, text)
            if match:
                return match.group(0)
        return text.strip()
    
    def _clean_number(self, text: str) -> str:
        # Remove all non-numeric except decimal point
        text = re.sub(r'[^0-9.]', '', text)
        
        # Handle multiple decimals
        parts = text.split('.')
        if len(parts) > 2:
            text = parts[0] + '.' + ''.join(parts[1:])
        
        # Validate
        try:
            float(text)
            return text
        except:
            return ''


# Singleton
_extractor = None

def extract_receipt_fields(image_bytes: bytes) -> Dict:
    """Main extraction function"""
    global _extractor
    if _extractor is None:
        _extractor = FieldExtractor()
    return _extractor.extract_all_fields(image_bytes)
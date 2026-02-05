# FILE: app/services/currency_service.py
# Currency note detection with improved accuracy
# ============================================================================

"""
Enhanced Currency Detection Service
Detect Sri Lankan currency notes using YOLO with strict validation
"""

from ultralytics import YOLO
from app.config.settings import CURRENCY_MODEL_PATH
import re
import os
import numpy as np
from typing import Dict, List
import cv2

# Load model
currency_model = None

def init_currency_model():
    """Initialize currency detection model"""
    global currency_model
    
    if os.path.exists(CURRENCY_MODEL_PATH):
        try:
            currency_model = YOLO(CURRENCY_MODEL_PATH)
            print("[CURRENCY] ✓ Model loaded successfully")
            return True
        except Exception as e:
            print(f"[CURRENCY] ✗ Failed to load model: {e}")
            return False
    else:
        print(f"[CURRENCY] ✗ Model not found: {CURRENCY_MODEL_PATH}")
        return False

# Try to initialize
init_currency_model()

# ============================================================================
# CURRENCY VALIDATOR
# ============================================================================

class CurrencyValidator:
    """Validate detected currency notes"""
    
    # Valid Sri Lankan currency denominations
    VALID_DENOMINATIONS = [20, 50, 100, 500, 1000, 5000]
    
    # Confidence threshold
    MIN_CONFIDENCE = 0.60  # 60% confidence (lowered for better detection)
    
    # Size constraints (normalized 0-1)
    MIN_WIDTH = 0.10   # Minimum 10% of image width
    MIN_HEIGHT = 0.05  # Minimum 5% of image height
    MAX_WIDTH = 0.99   # Maximum 99% of image width
    MAX_HEIGHT = 0.99  # Maximum 99% of image height
    
    # Relaxed aspect ratio constraints
    MIN_ASPECT_RATIO = 0.26   # Very flexible minimum
    MAX_ASPECT_RATIO = 3.8    # Very flexible maximum
    
    @staticmethod
    def is_valid_detection(detection: Dict, frame_shape: tuple) -> tuple[bool, str]:
        """
        Validate if detection is a real currency note
        
        Returns:
            (is_valid, reason)
        """
        # Check confidence
        confidence = detection.get('confidence', 0)
        if confidence < CurrencyValidator.MIN_CONFIDENCE:
            return False, f"Low confidence: {confidence:.2%}"
        
        # Check denomination
        amount = detection.get('amount', 0)
        if amount not in CurrencyValidator.VALID_DENOMINATIONS:
            return False, f"Invalid denomination: {amount}"
        
        # Check size
        width = detection.get('width', 0)
        height = detection.get('height', 0)
        
        if width < CurrencyValidator.MIN_WIDTH or height < CurrencyValidator.MIN_HEIGHT:
            return False, f"Too small: {width:.2%}x{height:.2%}"
        
        if width > CurrencyValidator.MAX_WIDTH or height > CurrencyValidator.MAX_HEIGHT:
            return False, f"Too large: {width:.2%}x{height:.2%}"
        
        # RELAXED aspect ratio check
        if height > 0:
            aspect_ratio = width / height
            
            # Reject only if completely outside reasonable range
            if aspect_ratio < CurrencyValidator.MIN_ASPECT_RATIO or aspect_ratio > CurrencyValidator.MAX_ASPECT_RATIO:
                return False, f"Extreme aspect ratio: {aspect_ratio:.2f}"
            
            # Reject perfect squares (likely not currency)
            if 0.95 <= aspect_ratio <= 1.05:
                return False, f"Too square: {aspect_ratio:.2f}"
        
        return True, "Valid"
    
    @staticmethod
    def remove_overlapping_detections(detections: List[Dict]) -> List[Dict]:
        """Remove overlapping detections, keep highest confidence"""
        if len(detections) <= 1:
            return detections
        
        # Sort by confidence (descending)
        sorted_detections = sorted(detections, key=lambda x: x['confidence'], reverse=True)
        
        filtered = []
        
        for detection in sorted_detections:
            is_overlap = False
            
            for existing in filtered:
                # Calculate IoU (Intersection over Union)
                iou = CurrencyValidator._calculate_iou(detection, existing)
                
                # If overlap is significant (>30%), skip this detection
                if iou > 0.3:
                    is_overlap = True
                    break
            
            if not is_overlap:
                filtered.append(detection)
        
        return filtered
    
    @staticmethod
    def _calculate_iou(det1: Dict, det2: Dict) -> float:
        """Calculate Intersection over Union between two detections"""
        # Get coordinates
        x1_1, y1_1 = det1['x1'], det1['y1']
        x2_1, y2_1 = det1['x2'], det1['y2']
        x1_2, y1_2 = det2['x1'], det2['y1']
        x2_2, y2_2 = det2['x2'], det2['y2']
        
        # Calculate intersection
        x1_i = max(x1_1, x1_2)
        y1_i = max(y1_1, y1_2)
        x2_i = min(x2_1, x2_2)
        y2_i = min(y2_1, y2_2)
        
        if x2_i < x1_i or y2_i < y1_i:
            return 0.0  # No intersection
        
        intersection = (x2_i - x1_i) * (y2_i - y1_i)
        
        # Calculate union
        area1 = (x2_1 - x1_1) * (y2_1 - y1_1)
        area2 = (x2_2 - x1_2) * (y2_2 - y1_2)
        union = area1 + area2 - intersection
        
        return intersection / union if union > 0 else 0.0

# ============================================================================
# CURRENCY DETECTOR
# ============================================================================

class CurrencyDetector:
    """Detect currency notes in images with high accuracy"""
    
    @staticmethod
    def detect(frame: np.ndarray) -> Dict:
        """
        Detect currency notes in image
        
        Args:
            frame: Image as numpy array (BGR format)
        
        Returns:
            Dict with message and detected items
        """
        if currency_model is None:
            return {
                'message': 'Currency detection not available',
                'items': []
            }
        
        try:
            # Run detection with higher confidence threshold
            results = currency_model(frame, conf=0.60, verbose=False)
            items = []
            
            if results and len(results) > 0:
                result = results[0]
                
                if hasattr(result, 'boxes') and result.boxes is not None:
                    class_indices = result.boxes.cls.cpu().numpy()
                    labels = [result.names[int(idx)] for idx in class_indices]
                    
                    for label in labels:
                        amount = CurrencyDetector._extract_amount(label)
                        if amount and amount in CurrencyValidator.VALID_DENOMINATIONS:
                            items.append({
                                'label': label,
                                'name': CurrencyDetector._format_name(label),
                                'amount': amount
                            })
            
            # Generate message
            message = CurrencyDetector._generate_message(items)
            
            return {
                'message': message,
                'items': items
            }
        
        except Exception as e:
            print(f"[CURRENCY ERROR] {e}")
            return {
                'message': 'Detection failed',
                'items': []
            }
    
    @staticmethod
    def detect_with_positions(frame: np.ndarray) -> Dict:
        """
        Detect currency with AR positioning data and strict validation
        
        Returns:
            Dict with detections including normalized bounding boxes
        """
        if currency_model is None:
            return {'detections': []}
        
        try:
            height, width = frame.shape[:2]
            
            # Run detection with confidence threshold
            results = currency_model(frame, conf=0.55, verbose=False)
            raw_detections = []
            
            if results and len(results) > 0:
                result = results[0]
                
                if hasattr(result, 'boxes') and result.boxes is not None:
                    boxes = result.boxes
                    
                    for box in boxes:
                        # Get bbox coordinates
                        xyxy = box.xyxy[0].cpu().numpy()
                        x1, y1, x2, y2 = xyxy
                        
                        # Normalize (0-1)
                        x1_norm = float(x1 / width)
                        y1_norm = float(y1 / height)
                        x2_norm = float(x2 / width)
                        y2_norm = float(y2 / height)
                        
                        # Calculate dimensions
                        box_width = x2_norm - x1_norm
                        box_height = y2_norm - y1_norm
                        
                        # Calculate center
                        center_x = (x1_norm + x2_norm) / 2
                        center_y = (y1_norm + y2_norm) / 2
                        
                        # Get class info
                        cls_idx = int(box.cls[0].cpu().numpy())
                        confidence = float(box.conf[0].cpu().numpy())
                        label = result.names[cls_idx]
                        
                        amount = CurrencyDetector._extract_amount(label)
                        
                        if amount:
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
                                'width': box_width,
                                'height': box_height
                            }
                            
                            # Validate detection
                            is_valid, reason = CurrencyValidator.is_valid_detection(
                                detection, (height, width)
                            )
                            
                            if is_valid:
                                raw_detections.append(detection)
                            else:
                                print(f"[CURRENCY] Rejected {label}: {reason}")
            
            # Remove overlapping detections
            filtered_detections = CurrencyValidator.remove_overlapping_detections(
                raw_detections
            )
            
            print(f"[CURRENCY] Detected: {len(raw_detections)} → Filtered: {len(filtered_detections)}")
            
            return {'detections': filtered_detections}
        
        except Exception as e:
            print(f"[CURRENCY ERROR] {e}")
            return {'detections': []}
    
    @staticmethod
    def _extract_amount(label: str) -> float:
        """Extract numeric amount from label"""
        numbers = re.findall(r'\d+', str(label))
        if numbers:
            try:
                amount = float(numbers[0])
                # Only return if it's a valid denomination
                if amount in CurrencyValidator.VALID_DENOMINATIONS:
                    return amount
            except:
                return None
        return None
    
    @staticmethod
    def _format_name(label: str) -> str:
        """Format currency name for display"""
        numbers = re.findall(r'\d+', str(label))
        if numbers:
            return f"{numbers[0]} rupees note"
        return str(label)
    
    @staticmethod
    def _generate_message(items: List[Dict]) -> str:
        """Generate voice announcement message"""
        if not items:
            return "No currency detected"
        
        if len(items) == 1:
            return f"This is {items[0]['name']}"
        
        # Multiple notes
        names = [item['name'] for item in items]
        if len(names) == 2:
            return f"I detected {names[0]} and {names[1]}"
        else:
            return f"I detected {', '.join(names[:-1])}, and {names[-1]}"
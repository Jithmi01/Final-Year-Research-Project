# FILE: app/services/currency_service.py
# Currency note detection
# ============================================================================

"""
Currency Detection Service
Detect Sri Lankan currency notes using YOLO
"""

from ultralytics import YOLO
from app.config.settings import CURRENCY_MODEL_PATH
import re
import os
import numpy as np
from typing import Dict, List

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
# CURRENCY DETECTOR
# ============================================================================

class CurrencyDetector:
    """Detect currency notes in images"""
    
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
            results = currency_model(frame, conf=0.5, verbose=False)
            items = []
            
            if results and len(results) > 0:
                result = results[0]
                
                if hasattr(result, 'boxes') and result.boxes is not None:
                    class_indices = result.boxes.cls.cpu().numpy()
                    labels = [result.names[int(idx)] for idx in class_indices]
                    
                    for label in labels:
                        amount = CurrencyDetector._extract_amount(label)
                        if amount:
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
        Detect currency with AR positioning data
        
        Returns:
            Dict with detections including normalized bounding boxes
        """
        if currency_model is None:
            return {'detections': []}
        
        try:
            height, width = frame.shape[:2]
            results = currency_model(frame, conf=0.5, verbose=False)
            detections = []
            
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
                        
                        # Calculate center
                        center_x = (x1_norm + x2_norm) / 2
                        center_y = (y1_norm + y2_norm) / 2
                        
                        # Get class info
                        cls_idx = int(box.cls[0].cpu().numpy())
                        confidence = float(box.conf[0].cpu().numpy())
                        label = result.names[cls_idx]
                        
                        amount = CurrencyDetector._extract_amount(label)
                        
                        if amount:
                            detections.append({
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
                                'height': y2_norm - y1_norm
                            })
            
            return {'detections': detections}
        
        except Exception as e:
            print(f"[CURRENCY ERROR] {e}")
            return {'detections': []}
    
    @staticmethod
    def _extract_amount(label: str) -> float:
        """Extract numeric amount from label"""
        numbers = re.findall(r'\d+', str(label))
        if numbers:
            try:
                return float(numbers[0])
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
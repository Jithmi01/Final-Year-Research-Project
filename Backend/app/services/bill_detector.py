# ============================================================================
# FILE: app/services/bill_detector.py
# Bill detection and positioning guidance for visually impaired users
# ============================================================================

import cv2
import numpy as np
from typing import Dict, Optional, Tuple
from dataclasses import dataclass

@dataclass
class BillPosition:
    """Represents bill position in frame"""
    detected: bool
    center_x: float  # 0.0 to 1.0 (percentage of frame width)
    center_y: float  # 0.0 to 1.0 (percentage of frame height)
    width: float     # 0.0 to 1.0 (percentage of frame width)
    height: float    # 0.0 to 1.0 (percentage of frame height)
    angle: float     # Rotation angle in degrees
    confidence: float  # 0.0 to 1.0

class BillDetector:
    """
    Detects bills in images and provides positioning guidance
    Specifically designed for visually impaired users
    """
    
    # Target positioning (bill should be in center)
    TARGET_CENTER_X = 0.5
    TARGET_CENTER_Y = 0.5
    TARGET_SIZE_MIN = 0.25  # Bill should occupy at least 25% of frame
    TARGET_SIZE_MAX = 0.70  # Bill should not occupy more than 70% of frame
    TARGET_SIZE_OPTIMAL = 0.45  # Optimal: 45% of frame
    
    # Tolerance zones
    CENTER_TOLERANCE = 0.15  # 15% deviation acceptable
    ANGLE_TOLERANCE = 15.0   # 15 degrees tilt acceptable
    
    def __init__(self):
        """Initialize bill detector"""
        self.last_position = None
    
    def detect_bill(self, image: np.ndarray) -> Dict:
        """
        Detect bill in image and provide positioning guidance
        
        Returns:
            {
                'bill_detected': bool,
                'position': BillPosition or None,
                'guidance': str,  # Voice guidance
                'direction': str,  # 'center', 'left', 'right', 'up', 'down'
                'is_centered': bool,
                'is_correct_size': bool,
                'is_level': bool,
                'ready_to_scan': bool
            }
        """
        if image is None or image.size == 0:
            return self._create_no_detection_result("No image provided")
        
        height, width = image.shape[:2]
        
        # Detect bill contour
        bill_contour, confidence = self._find_bill_contour(image)
        
        if bill_contour is None:
            return self._create_no_detection_result("No bill detected. Hold bill in front of camera.")
        
        # Calculate bill position
        position = self._calculate_position(bill_contour, width, height, confidence)
        
        # Generate guidance
        guidance_data = self._generate_guidance(position, width, height)
        
        return {
            'bill_detected': True,
            'position': position,
            'guidance': guidance_data['message'],
            'direction': guidance_data['direction'],
            'is_centered': guidance_data['is_centered'],
            'is_correct_size': guidance_data['is_correct_size'],
            'is_level': guidance_data['is_level'],
            'ready_to_scan': guidance_data['ready_to_scan']
        }
    
    def _find_bill_contour(self, image: np.ndarray) -> Tuple[Optional[np.ndarray], float]:
        """
        Find bill contour using edge detection and shape analysis
        VERY LENIENT - accepts any rectangular object
        Returns: (contour, confidence)
        """
        try:
            # Convert to grayscale
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            
            # Simple threshold - works better than Canny for bills
            _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            
            # Invert if needed (white bill on dark background)
            if np.mean(thresh) > 127:
                thresh = cv2.bitwise_not(thresh)
            
            # Find contours
            contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            
            print(f"[BILL DETECTOR] Found {len(contours)} contours")
            
            if not contours:
                return None, 0.0
            
            # Get image area
            image_area = image.shape[0] * image.shape[1]
            
            # Find largest contour
            largest_contour = max(contours, key=cv2.contourArea)
            largest_area = cv2.contourArea(largest_contour)
            area_percentage = largest_area / image_area
            
            print(f"[BILL DETECTOR] Largest contour: {area_percentage*100:.1f}% of image")
            
            # IMPORTANT: Only detect bills that are reasonable size for OCR
            # Detection threshold should match TARGET_SIZE_MIN
            if area_percentage < 0.20:  # Less than 20% - too small
                print(f"[BILL DETECTOR] ✗ Bill too small ({area_percentage*100:.1f}%), need 20%+")
                return None, 0.0
            
            # Accept bills between 20% and 95% of frame
            if 0.20 <= area_percentage <= 0.95:
                # Calculate confidence
                confidence = min(1.0, area_percentage / 0.5)
                print(f"[BILL DETECTOR] ✓ Bill detected with {confidence:.2f} confidence")
                return largest_contour, confidence
            
            print(f"[BILL DETECTOR] ✗ Contour too large ({area_percentage*100:.1f}%)")
            return None, 0.0
            
        except Exception as e:
            print(f"[BILL DETECTOR ERROR] {e}")
            import traceback
            traceback.print_exc()
            return None, 0.0
    
    def _calculate_position(self, contour: np.ndarray, frame_width: int, 
                           frame_height: int, confidence: float) -> BillPosition:
        """Calculate bill position and orientation"""
        # Get bounding rectangle
        x, y, w, h = cv2.boundingRect(contour)
        
        # Calculate center (as percentage of frame)
        center_x = (x + w / 2) / frame_width
        center_y = (y + h / 2) / frame_height
        
        # Calculate size (as percentage of frame)
        width_pct = w / frame_width
        height_pct = h / frame_height
        
        # Calculate rotation angle
        if len(contour) >= 5:
            ellipse = cv2.fitEllipse(contour)
            angle = ellipse[2]
            
            # Normalize angle to -90 to 90
            if angle > 90:
                angle = angle - 180
        else:
            angle = 0.0
        
        return BillPosition(
            detected=True,
            center_x=center_x,
            center_y=center_y,
            width=width_pct,
            height=height_pct,
            angle=angle,
            confidence=confidence
        )
    
    def _generate_guidance(self, position: BillPosition, 
                          frame_width: int, frame_height: int) -> Dict:
        """
        Generate positioning guidance for visually impaired users
        Provides clear directional commands
        """
        # Check if centered
        x_diff = position.center_x - self.TARGET_CENTER_X
        y_diff = position.center_y - self.TARGET_CENTER_Y
        
        is_x_centered = abs(x_diff) <= self.CENTER_TOLERANCE
        is_y_centered = abs(y_diff) <= self.CENTER_TOLERANCE
        is_centered = is_x_centered and is_y_centered
        
        # Check if correct size - USE WIDER ACCEPTABLE RANGE
        bill_size = max(position.width, position.height)
        
        # Acceptable range is wider than "optimal" to reduce constant adjustments
        SIZE_ACCEPTABLE_MIN = 0.22  # Accept if 22%+ (slightly below target)
        SIZE_ACCEPTABLE_MAX = 0.75  # Accept if up to 75% (slightly above target)
        
        is_correct_size = SIZE_ACCEPTABLE_MIN <= bill_size <= SIZE_ACCEPTABLE_MAX
        
        # Check if level (not tilted)
        is_level = abs(position.angle) <= self.ANGLE_TOLERANCE
        
        # Ready to scan if all conditions met
        ready_to_scan = is_centered and is_correct_size and is_level
        
        # Generate direction and message
        if ready_to_scan:
            return {
                'message': 'Perfect. Bill is centered. Ready to scan.',
                'direction': 'center',
                'is_centered': True,
                'is_correct_size': True,
                'is_level': True,
                'ready_to_scan': True
            }
        
        # Priority 1: Size (too close or too far)
        # Only complain if REALLY outside acceptable range
        if bill_size < SIZE_ACCEPTABLE_MIN:
            return {
                'message': 'Move closer to bill.',
                'direction': 'closer',
                'is_centered': is_centered,
                'is_correct_size': False,
                'is_level': is_level,
                'ready_to_scan': False
            }
        elif bill_size > SIZE_ACCEPTABLE_MAX:
            return {
                'message': 'Move back. Bill too close.',
                'direction': 'farther',
                'is_centered': is_centered,
                'is_correct_size': False,
                'is_level': is_level,
                'ready_to_scan': False
            }
        
        # Priority 2: Tilt/Rotation
        if not is_level:
            if abs(position.angle) > self.ANGLE_TOLERANCE:
                tilt_dir = 'clockwise' if position.angle > 0 else 'counter-clockwise'
                return {
                    'message': f'Rotate bill slightly.',
                    'direction': 'rotate',
                    'is_centered': is_centered,
                    'is_correct_size': is_correct_size,
                    'is_level': False,
                    'ready_to_scan': False
                }
        
        # Priority 3: Horizontal position (left/right)
        if not is_x_centered:
            if x_diff > self.CENTER_TOLERANCE:
                return {
                    'message': 'Move camera left.',
                    'direction': 'left',
                    'is_centered': False,
                    'is_correct_size': is_correct_size,
                    'is_level': is_level,
                    'ready_to_scan': False
                }
            else:
                return {
                    'message': 'Move camera right.',
                    'direction': 'right',
                    'is_centered': False,
                    'is_correct_size': is_correct_size,
                    'is_level': is_level,
                    'ready_to_scan': False
                }
        
        # Priority 4: Vertical position (up/down)
        if not is_y_centered:
            if y_diff > self.CENTER_TOLERANCE:
                return {
                    'message': 'Move camera up.',
                    'direction': 'up',
                    'is_centered': False,
                    'is_correct_size': is_correct_size,
                    'is_level': is_level,
                    'ready_to_scan': False
                }
            else:
                return {
                    'message': 'Move camera down.',
                    'direction': 'down',
                    'is_centered': False,
                    'is_correct_size': is_correct_size,
                    'is_level': is_level,
                    'ready_to_scan': False
                }
        
        # Fallback (should not reach here)
        return {
            'message': 'Adjust camera position.',
            'direction': 'adjust',
            'is_centered': is_centered,
            'is_correct_size': is_correct_size,
            'is_level': is_level,
            'ready_to_scan': False
        }
    
    def _create_no_detection_result(self, message: str) -> Dict:
        """Create result when no bill is detected"""
        return {
            'bill_detected': False,
            'position': None,
            'guidance': message,
            'direction': 'none',
            'is_centered': False,
            'is_correct_size': False,
            'is_level': False,
            'ready_to_scan': False
        }


# Singleton instance
_bill_detector = None

def get_bill_detector():
    """Get bill detector instance"""
    global _bill_detector
    if _bill_detector is None:
        _bill_detector = BillDetector()
    return _bill_detector


def detect_bill_position(image_bytes: bytes) -> Dict:
    """
    Main function to detect bill and get positioning guidance
    
    Args:
        image_bytes: Image as bytes
    
    Returns:
        Detection result with positioning guidance
    """
    # Decode image
    nparr = np.frombuffer(image_bytes, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    if image is None:
        return {
            'bill_detected': False,
            'guidance': 'Cannot read image',
            'direction': 'none',
            'ready_to_scan': False
        }
    
    detector = get_bill_detector()
    return detector.detect_bill(image)
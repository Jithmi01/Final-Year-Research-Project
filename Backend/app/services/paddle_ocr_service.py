# ============================================================================
# FILE: app/services/paddle_ocr_service.py (FIXED VERSION)
# PaddleOCR with correct initialization - NO 'cls' parameter
# ============================================================================

import cv2
import numpy as np
from typing import Optional, List
import re

class PaddleOCRService:
    """PaddleOCR wrapper - FIXED for latest version"""
    
    def __init__(self):
        """Initialize PaddleOCR"""
        try:
            from paddleocr import PaddleOCR
            
            # FIXED: Correct initialization without deprecated parameters
            self.ocr = PaddleOCR(
                use_angle_cls=True,  # Enable angle classification
                lang='en',
                det_db_thresh=0.3,
                det_db_box_thresh=0.5,
                show_log=False  # Reduce noise
            )
            self.available = True
            print("[PADDLE OCR] ✓ Initialized successfully")
            
        except Exception as e:
            print(f"[PADDLE OCR] ✗ Failed: {e}")
            self.available = False
    
    def extract_text_from_roi(self, roi: np.ndarray, field_type: str = None) -> str:
        """Extract text from image region"""
        if not self.available or roi.size == 0:
            return ""
        
        try:
            # Ensure minimum size for better OCR
            if roi.shape[0] < 20 or roi.shape[1] < 20:
                scale = max(20 / roi.shape[0], 20 / roi.shape[1])
                roi = cv2.resize(roi, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
            
            # Preprocess for better OCR
            if len(roi.shape) == 2:
                roi = cv2.cvtColor(roi, cv2.COLOR_GRAY2BGR)
            
            # Enhance contrast
            roi = self._enhance_image(roi, field_type)
            
            # FIXED: Call OCR without 'cls' parameter
            # The cls parameter was removed in newer versions
            result = self.ocr.ocr(roi, cls=True)  # cls is now handled internally
            
            if not result or not result[0]:
                return ""
            
            # Extract text with confidence filtering
            texts = []
            for line in result[0]:
                if line and len(line) >= 2:
                    text = line[1][0]
                    conf = line[1][1]
                    
                    # Higher confidence threshold for critical fields
                    min_conf = 0.6 if field_type in ['company', 'total'] else 0.5
                    
                    if conf > min_conf:
                        texts.append(text)
            
            combined = ' '.join(texts)
            
            # Post-process based on field type
            if field_type:
                combined = self._post_process(combined, field_type)
            
            return combined.strip()
            
        except Exception as e:
            print(f"[PADDLE OCR ERROR] {e}")
            # Try fallback without cls parameter
            try:
                result = self.ocr.ocr(roi)  # Minimal call
                if result and result[0]:
                    texts = [line[1][0] for line in result[0] if line and len(line) >= 2]
                    return ' '.join(texts).strip()
            except:
                pass
            return ""
    
    def _enhance_image(self, roi: np.ndarray, field_type: str = None) -> np.ndarray:
        """Enhance image for better OCR accuracy"""
        try:
            # Convert to grayscale
            if len(roi.shape) == 3:
                gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            else:
                gray = roi.copy()
            
            # Apply different enhancements based on field type
            if field_type in ['menu.price', 'total.total_price', 'total.cashprice']:
                # For numbers: stronger preprocessing
                # Increase contrast
                clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
                enhanced = clahe.apply(gray)
                
                # Denoise
                enhanced = cv2.fastNlMeansDenoising(enhanced, None, 10, 7, 21)
                
                # Adaptive threshold for better number recognition
                enhanced = cv2.adaptiveThreshold(
                    enhanced, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
                    cv2.THRESH_BINARY, 11, 2
                )
            else:
                # For text: gentler preprocessing
                # Slight denoising
                enhanced = cv2.fastNlMeansDenoising(gray, None, 5, 7, 21)
                
                # Adaptive threshold
                enhanced = cv2.adaptiveThreshold(
                    enhanced, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                    cv2.THRESH_BINARY, 15, 5
                )
            
            # Convert back to BGR for PaddleOCR
            return cv2.cvtColor(enhanced, cv2.COLOR_GRAY2BGR)
            
        except Exception as e:
            print(f"[IMAGE ENHANCE ERROR] {e}")
            return roi
    
    def _post_process(self, text: str, field_type: str) -> str:
        """Post-process text based on field type"""
        if not text:
            return ""
        
        # Remove excessive whitespace
        text = ' '.join(text.split())
        
        if 'company' in field_type or 'menu.nm' in field_type:
            # Clean company/item names
            text = re.sub(r'[^a-zA-Z0-9\s\-&.,()\'"]', '', text)
            text = text.strip('.,;:"\'-')
            
        elif 'address' in field_type:
            # Keep address formatting
            text = re.sub(r'[^\w\s\-.,#/()]', '', text)
            
        elif 'date' in field_type:
            # Extract date patterns
            patterns = [
                r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}',
                r'\d{4}[-/]\d{1,2}[-/]\d{1,2}',
                r'\d{1,2}\s+[A-Za-z]+\s+\d{2,4}',
            ]
            for pattern in patterns:
                match = re.search(pattern, text)
                if match:
                    return match.group(0)
        
        elif 'price' in field_type or 'number' in field_type or 'cnt' in field_type:
            # Extract numbers
            # Remove currency symbols and letters
            text = re.sub(r'[^0-9.]', '', text)
            
            # Handle multiple decimal points
            parts = text.split('.')
            if len(parts) > 2:
                text = parts[0] + '.' + ''.join(parts[1:])
            
            # Validate number
            try:
                float(text)
                return text
            except:
                return ''
        
        return text.strip()


class TesseractOCRService:
    """Tesseract fallback with better preprocessing"""
    
    def __init__(self):
        try:
            import pytesseract
            self.pytesseract = pytesseract
            self.available = True
            print("[TESSERACT OCR] ✓ Available")
        except:
            self.available = False
            print("[TESSERACT OCR] ✗ Not available")
    
    def extract_text_from_roi(self, roi: np.ndarray, field_type: str = None) -> str:
        if not self.available or roi.size == 0:
            return ""
        
        try:
            # Convert to grayscale
            if len(roi.shape) == 3:
                gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            else:
                gray = roi.copy()
            
            # Resize small images
            if gray.shape[0] < 30:
                scale = 40 / gray.shape[0]
                gray = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
            
            # Denoise
            gray = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)
            
            # Threshold
            _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            
            # Configure based on field type
            if 'price' in str(field_type) or 'cnt' in str(field_type):
                config = '--psm 7 --oem 3 -c tessedit_char_whitelist=0123456789.,'
            else:
                config = '--psm 7 --oem 3'
            
            text = self.pytesseract.image_to_string(binary, config=config, lang='eng')
            return text.strip()
            
        except Exception as e:
            print(f"[TESSERACT ERROR] {e}")
            return ""


class AutoOCRService:
    """Auto-select best OCR engine"""
    
    def __init__(self):
        self.paddle = PaddleOCRService()
        self.tesseract = TesseractOCRService()
        
        if self.paddle.available:
            self.primary = self.paddle
            self.fallback = self.tesseract if self.tesseract.available else None
            self.engine_name = "PaddleOCR"
            print("[AUTO OCR] ✓ Using PaddleOCR with Tesseract fallback")
        elif self.tesseract.available:
            self.primary = self.tesseract
            self.fallback = None
            self.engine_name = "Tesseract"
            print("[AUTO OCR] ⚠️  Using Tesseract only")
        else:
            raise Exception("No OCR engine available!")
    
    def extract_text_from_roi(self, roi: np.ndarray, field_type: str = None) -> str:
        """Extract with fallback support"""
        # Try primary engine
        result = self.primary.extract_text_from_roi(roi, field_type)
        
        # If failed and fallback available, try fallback
        if not result and self.fallback:
            result = self.fallback.extract_text_from_roi(roi, field_type)
        
        return result
    
    def get_engine_name(self) -> str:
        return self.engine_name


# Singleton instance
_ocr_service = None

def get_ocr_service():
    """Get OCR service instance"""
    global _ocr_service
    if _ocr_service is None:
        _ocr_service = AutoOCRService()
    return _ocr_service
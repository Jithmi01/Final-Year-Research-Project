# ============================================================================
# FILE: app/services/enhanced_ocr_service.py
# Enhanced OCR with multiple engines and better preprocessing
# ============================================================================

"""
Enhanced OCR Service
Uses multiple OCR engines and advanced preprocessing for better accuracy
"""

import cv2
import numpy as np
import pytesseract
from typing import Tuple, Optional
import re

class EnhancedOCR:
    """Enhanced OCR with advanced preprocessing"""
    
    @staticmethod
    def extract_text_from_roi(
        roi: np.ndarray,
        field_type: str,
        use_aggressive_preprocessing: bool = True
    ) -> str:
        """
        Extract text with advanced preprocessing
        
        Args:
            roi: Region of interest
            field_type: Type of field (company, address, date, menu.nm, etc.)
            use_aggressive_preprocessing: Apply aggressive preprocessing
        
        Returns:
            Extracted text
        """
        if roi.size == 0:
            return ""
        
        try:
            # Step 1: Resize if too small
            if roi.shape[0] < 30 or roi.shape[1] < 30:
                scale = max(30 / roi.shape[0], 30 / roi.shape[1])
                roi = cv2.resize(roi, None, fx=scale, fy=scale, 
                               interpolation=cv2.INTER_CUBIC)
            
            # Step 2: Convert to grayscale
            if len(roi.shape) == 3:
                gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            else:
                gray = roi.copy()
            
            # Step 3: Denoise
            if use_aggressive_preprocessing:
                gray = cv2.fastNlMeansDenoising(gray, None, h=10, 
                                              templateWindowSize=7, 
                                              searchWindowSize=21)
            
            # Step 4: Enhance contrast with CLAHE
            clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
            enhanced = clahe.apply(gray)
            
            # Step 5: Sharpen
            if use_aggressive_preprocessing:
                kernel = np.array([[-1,-1,-1], [-1, 9,-1], [-1,-1,-1]])
                enhanced = cv2.filter2D(enhanced, -1, kernel)
            
            # Step 6: Binarization - try multiple methods
            results = []
            
            # Method 1: Otsu's thresholding
            _, binary1 = cv2.threshold(enhanced, 0, 255, 
                                      cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            text1 = EnhancedOCR._ocr_with_config(binary1, field_type)
            if text1:
                results.append((text1, EnhancedOCR._score_text(text1, field_type)))
            
            # Method 2: Adaptive Gaussian
            binary2 = cv2.adaptiveThreshold(enhanced, 255, 
                                           cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                           cv2.THRESH_BINARY, 11, 2)
            text2 = EnhancedOCR._ocr_with_config(binary2, field_type)
            if text2:
                results.append((text2, EnhancedOCR._score_text(text2, field_type)))
            
            # Method 3: Try inverted
            _, binary3 = cv2.threshold(enhanced, 0, 255, 
                                      cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
            text3 = EnhancedOCR._ocr_with_config(binary3, field_type)
            if text3:
                results.append((text3, EnhancedOCR._score_text(text3, field_type)))
            
            # Select best result
            if results:
                best_text = max(results, key=lambda x: x[1])[0]
                return EnhancedOCR._post_process(best_text, field_type)
            
            return ""
            
        except Exception as e:
            print(f"[ENHANCED OCR ERROR] {e}")
            return ""
    
    @staticmethod
    def _ocr_with_config(image: np.ndarray, field_type: str) -> str:
        """Run OCR with field-specific configuration"""
        try:
            # Field-specific PSM modes
            if 'company' in field_type or 'nm' in field_type or 'name' in field_type:
                # Single line of text
                config = '--psm 7 --oem 3'
            elif 'address' in field_type:
                # Multiple lines
                config = '--psm 6 --oem 3'
            elif 'date' in field_type:
                # Single line with dates
                config = '--psm 7 --oem 3'
            elif 'price' in field_type or 'total' in field_type or 'cnt' in field_type or 'count' in field_type or 'cash' in field_type or 'change' in field_type:
                # Numbers only
                config = '--psm 7 --oem 3 -c tessedit_char_whitelist=0123456789.,'
            else:
                config = '--psm 7 --oem 3'
            
            text = pytesseract.image_to_string(image, config=config, lang='eng')
            return text.strip()
            
        except Exception as e:
            return ""
    
    @staticmethod
    def _score_text(text: str, field_type: str) -> float:
        """Score OCR result quality"""
        if not text or not text.strip():
            return 0.0
        
        score = 0.0
        text_clean = text.strip()
        
        # Length score
        length = len(text_clean)
        if length > 2:
            score += min(length / 10, 5.0)
        
        # Character type score
        alpha_count = sum(c.isalpha() for c in text_clean)
        digit_count = sum(c.isdigit() for c in text_clean)
        space_count = sum(c.isspace() for c in text_clean)
        
        if 'company' in field_type or 'nm' in field_type or 'name' in field_type:
            # Prefer alphabetic characters
            score += alpha_count * 0.5
            score += (space_count * 0.3)  # Words separated by spaces
            score -= digit_count * 0.2  # Penalize too many numbers
            
        elif 'price' in field_type or 'total' in field_type or 'cnt' in field_type or 'cash' in field_type or 'change' in field_type:
            # Prefer numbers
            score += digit_count * 1.0
            if '.' in text_clean:
                score += 2.0  # Decimal point
            score -= alpha_count * 0.5  # Penalize letters
            
        elif 'date' in field_type:
            # Date patterns
            if re.search(r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}', text_clean):
                score += 10.0
            if re.search(r'\d{4}[-/]\d{1,2}[-/]\d{1,2}', text_clean):
                score += 10.0
            score += digit_count * 0.3
        
        # Penalize excessive special characters
        special = len(re.findall(r'[^\w\s.,:\-/()]', text_clean))
        score -= special * 0.5
        
        # Penalize very short text
        if length < 3:
            score -= 2.0
        
        return max(0, score)
    
    @staticmethod
    def _post_process(text: str, field_type: str) -> str:
        """Clean and validate extracted text"""
        if not text:
            return ""
        
        # Remove excessive whitespace
        text = ' '.join(text.split())
        
        if 'company' in field_type or 'nm' in field_type or 'name' in field_type:
            # Clean company/menu names
            # Remove common OCR errors
            text = re.sub(r'[|_~`]', '', text)  # Remove common noise
            text = re.sub(r'\s+', ' ', text)    # Single spaces
            text = text.strip('.,;:')           # Remove trailing punctuation
            
            # Remove if too short
            if len(text) < 2:
                return ""
            
        elif 'price' in field_type or 'total' in field_type or 'cnt' in field_type or 'cash' in field_type or 'change' in field_type:
            # Clean numbers
            text = re.sub(r'[^0-9.]', '', text)
            
            # Fix multiple decimals
            parts = text.split('.')
            if len(parts) > 2:
                text = parts[0] + '.' + ''.join(parts[1:])
            
            # Validate number
            try:
                if text and float(text) >= 0:
                    return text
                return ""
            except:
                return ""
        
        elif 'date' in field_type:
            # Clean date
            # Look for date patterns
            patterns = [
                r'(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})',
                r'(\d{4}[-/]\d{1,2}[-/]\d{1,2})',
                r'(\d{1,2}\s+\w{3,}\s+\d{2,4})'
            ]
            
            for pattern in patterns:
                match = re.search(pattern, text)
                if match:
                    return match.group(1)
            
            return text
        
        elif 'address' in field_type:
            # Clean address
            # Remove excessive special characters
            text = re.sub(r'[^\w\s.,\-#/()]', '', text)
            text = ' '.join(text.split())
        
        return text.strip()


class PaddleOCRService:
    """
    Alternative: PaddleOCR Service (if you want to use PaddleOCR)
    PaddleOCR is more accurate than Tesseract but requires installation
    
    Installation:
    pip install paddlepaddle paddleocr
    """
    
    def __init__(self):
        """Initialize PaddleOCR"""
        try:
            from paddleocr import PaddleOCR
            self.ocr = PaddleOCR(use_angle_cls=True, lang='en', 
                                use_gpu=False, show_log=False)
            self.available = True
            print("[PADDLE OCR] ✓ Initialized")
        except Exception as e:
            print(f"[PADDLE OCR] Not available: {e}")
            self.available = False
    
    def extract_text_from_roi(self, roi: np.ndarray, field_type: str) -> str:
        """Extract text using PaddleOCR"""
        if not self.available:
            return ""
        
        try:
            result = self.ocr.ocr(roi, cls=True)
            
            if result and result[0]:
                texts = [line[1][0] for line in result[0]]
                text = ' '.join(texts)
                return EnhancedOCR._post_process(text, field_type)
            
            return ""
            
        except Exception as e:
            print(f"[PADDLE OCR ERROR] {e}")
            return ""


class EasyOCRService:
    """
    Alternative: EasyOCR Service
    EasyOCR is another strong alternative to Tesseract
    
    Installation:
    pip install easyocr
    """
    
    def __init__(self):
        """Initialize EasyOCR"""
        try:
            import easyocr
            self.reader = easyocr.Reader(['en'], gpu=False)
            self.available = True
            print("[EASY OCR] ✓ Initialized")
        except Exception as e:
            print(f"[EASY OCR] Not available: {e}")
            self.available = False
    
    def extract_text_from_roi(self, roi: np.ndarray, field_type: str) -> str:
        """Extract text using EasyOCR"""
        if not self.available:
            return ""
        
        try:
            result = self.reader.readtext(roi)
            
            if result:
                texts = [item[1] for item in result]
                text = ' '.join(texts)
                return EnhancedOCR._post_process(text, field_type)
            
            return ""
            
        except Exception as e:
            print(f"[EASY OCR ERROR] {e}")
            return ""


# ============================================================================
# HYBRID OCR SERVICE (Uses best available OCR)
# ============================================================================

class HybridOCR:
    """Hybrid OCR that tries multiple engines"""
    
    def __init__(self):
        """Initialize all available OCR engines"""
        self.enhanced_ocr = EnhancedOCR()
        
        # Try to initialize alternative OCRs
        try:
            self.paddle_ocr = PaddleOCRService()
        except:
            self.paddle_ocr = None
        
        try:
            self.easy_ocr = EasyOCRService()
        except:
            self.easy_ocr = None
        
        print("[HYBRID OCR] ✓ Initialized")
    
    def extract_text(self, roi: np.ndarray, field_type: str) -> str:
        """Extract text using best available method"""
        results = []
        
        # Try Enhanced Tesseract
        text1 = self.enhanced_ocr.extract_text_from_roi(roi, field_type)
        if text1:
            score1 = EnhancedOCR._score_text(text1, field_type)
            results.append((text1, score1, 'EnhancedTesseract'))
        
        # Try PaddleOCR if available
        if self.paddle_ocr and self.paddle_ocr.available:
            text2 = self.paddle_ocr.extract_text_from_roi(roi, field_type)
            if text2:
                score2 = EnhancedOCR._score_text(text2, field_type)
                results.append((text2, score2, 'PaddleOCR'))
        
        # Try EasyOCR if available
        if self.easy_ocr and self.easy_ocr.available:
            text3 = self.easy_ocr.extract_text_from_roi(roi, field_type)
            if text3:
                score3 = EnhancedOCR._score_text(text3, field_type)
                results.append((text3, score3, 'EasyOCR'))
        
        # Return best result
        if results:
            best = max(results, key=lambda x: x[1])
            print(f"[HYBRID OCR] Best: {best[2]} (score: {best[1]:.2f})")
            return best[0]
        
        return ""
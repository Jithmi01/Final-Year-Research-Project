# ============================================================================
# FILE: app/services/ocr_service.py
# OCR text extraction with multiple enhancement methods
# ============================================================================

"""
OCR Service - Text Extraction from Images
Uses Tesseract with multiple preprocessing techniques for maximum accuracy
"""

import cv2
import pytesseract
import numpy as np
from PIL import Image
import re
from typing import List, Dict, Tuple
from config.settings import OCR_CONFIG

# ============================================================================
# IMAGE ENHANCEMENT
# ============================================================================

class ImageEnhancer:
    """Advanced image preprocessing for better OCR accuracy"""
    
    @staticmethod
    def analyze_image(image_array: np.ndarray) -> Dict:
        """
        Analyze image quality metrics
        
        Returns:
            Dict with brightness, contrast, and enhancement recommendations
        """
        gray = cv2.cvtColor(image_array, cv2.COLOR_BGR2GRAY) if len(image_array.shape) == 3 else image_array
        
        brightness = np.mean(gray)
        contrast = gray.std()
        
        needs_enhancement = brightness < 100 or brightness > 200 or contrast < 30
        
        return {
            'brightness': brightness,
            'contrast': contrast,
            'needs_enhancement': needs_enhancement
        }
    
    @staticmethod
    def denoise(image: np.ndarray) -> np.ndarray:
        """Remove noise from image"""
        if len(image.shape) == 3:
            return cv2.fastNlMeansDenoisingColored(image, None, 10, 10, 7, 21)
        else:
            return cv2.fastNlMeansDenoising(image, None, 10, 7, 21)
    
    @staticmethod
    def enhance_contrast(image: np.ndarray) -> np.ndarray:
        """Enhance image contrast using CLAHE"""
        if len(image.shape) == 3:
            lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
            l, a, b = cv2.split(lab)
        else:
            l = image
            a = b = None
        
        # Apply CLAHE (Contrast Limited Adaptive Histogram Equalization)
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        l = clahe.apply(l)
        
        # Merge back
        if a is not None and b is not None:
            lab = cv2.merge([l, a, b])
            return cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
        else:
            return l
    
    @staticmethod
    def sharpen(image: np.ndarray) -> np.ndarray:
        """Sharpen image for better text clarity"""
        kernel = np.array([
            [-1, -1, -1],
            [-1,  9, -1],
            [-1, -1, -1]
        ])
        return cv2.filter2D(image, -1, kernel)
    
    @staticmethod
    def binarize(image: np.ndarray) -> List[np.ndarray]:
        """
        Create multiple binarized versions using different methods
        
        Returns:
            List of binarized images
        """
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
        
        versions = []
        
        # Method 1: Otsu's thresholding (automatic threshold selection)
        _, otsu = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        versions.append(otsu)
        
        # Method 2: Adaptive Gaussian thresholding
        adaptive_gaussian = cv2.adaptiveThreshold(
            gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
            cv2.THRESH_BINARY, 11, 2
        )
        versions.append(adaptive_gaussian)
        
        # Method 3: Adaptive Mean thresholding
        adaptive_mean = cv2.adaptiveThreshold(
            gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C, 
            cv2.THRESH_BINARY, 15, 3
        )
        versions.append(adaptive_mean)
        
        return versions
    
    @staticmethod
    def full_pipeline(image_bytes: bytes) -> Dict[str, any]:
        """
        Complete preprocessing pipeline
        
        Args:
            image_bytes: Raw image bytes
        
        Returns:
            Dict with original, enhanced, and binarized versions
        """
        print("[OCR] Running preprocessing pipeline...")
        
        # Decode image
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            print("[OCR] ✗ Failed to decode image")
            return None
        
        # Step 1: Denoise
        denoised = ImageEnhancer.denoise(image)
        print("  ✓ Denoised")
        
        # Step 2: Enhance contrast
        enhanced = ImageEnhancer.enhance_contrast(denoised)
        print("  ✓ Contrast enhanced")
        
        # Step 3: Sharpen
        sharpened = ImageEnhancer.sharpen(enhanced)
        print("  ✓ Sharpened")
        
        # Step 4: Create binarized versions
        binarized = ImageEnhancer.binarize(sharpened)
        print(f"  ✓ Created {len(binarized)} binary versions")
        
        return {
            'original': image,
            'enhanced': sharpened,
            'binarized': binarized
        }

# ============================================================================
# OCR ENGINE
# ============================================================================

class OCREngine:
    """Main OCR extraction engine with multiple methods"""
    
    @staticmethod
    def extract_text(image_bytes: bytes) -> str:
        """
        Extract text using multiple preprocessing and PSM modes
        Returns best result based on quality scoring
        
        Args:
            image_bytes: Raw image bytes
        
        Returns:
            Extracted text string
        """
        print("[OCR] Starting text extraction...")
        
        try:
            # Preprocess image
            preprocessed = ImageEnhancer.full_pipeline(image_bytes)
            
            if not preprocessed:
                return ""
            
            # Try multiple methods and collect results
            results = []
            
            # Method 1: Original image with different PSM modes
            print("[OCR] Trying original image...")
            for psm in OCR_CONFIG['psm_modes']:
                text, score = OCREngine._extract_with_psm(
                    preprocessed['original'], psm, 'Original'
                )
                if text:
                    results.append({
                        'text': text, 
                        'score': score, 
                        'method': f'Original PSM-{psm}'
                    })
            
            # Method 2: Enhanced image with different PSM modes
            print("[OCR] Trying enhanced image...")
            for psm in OCR_CONFIG['psm_modes']:
                text, score = OCREngine._extract_with_psm(
                    preprocessed['enhanced'], psm, 'Enhanced'
                )
                if text:
                    results.append({
                        'text': text, 
                        'score': score, 
                        'method': f'Enhanced PSM-{psm}'
                    })
            
            # Method 3: Each binarized version
            for i, binary in enumerate(preprocessed['binarized']):
                print(f"[OCR] Trying binary version {i+1}...")
                for psm in OCR_CONFIG['psm_modes']:
                    text, score = OCREngine._extract_with_psm(
                        binary, psm, f'Binary-{i+1}'
                    )
                    if text:
                        results.append({
                            'text': text, 
                            'score': score, 
                            'method': f'Binary-{i+1} PSM-{psm}'
                        })
            
            # Select best result based on score
            if results:
                best = max(results, key=lambda x: x['score'])
                print(f"[OCR] ✓ Best method: {best['method']} (score: {best['score']:.1f})")
                print(f"[OCR] ✓ Extracted {len(best['text'])} characters")
                return best['text']
            
            print("[OCR] ⚠️  No text extracted")
            return ""
            
        except Exception as e:
            print(f"[OCR ERROR] {e}")
            import traceback
            traceback.print_exc()
            return ""
    
    @staticmethod
    def _extract_with_psm(image: np.ndarray, psm: int, method_name: str) -> Tuple[str, float]:
        """
        Extract text with specific PSM (Page Segmentation Mode)
        
        Args:
            image: Image as numpy array
            psm: Page segmentation mode (3, 4, 6, 11, etc.)
            method_name: Name of preprocessing method used
        
        Returns:
            Tuple of (text, quality_score)
        """
        try:
            config = f'--psm {psm} --oem 3'
            text = pytesseract.image_to_string(image, config=config, lang='eng')
            
            if text and text.strip():
                score = OCREngine._score_quality(text)
                return (text, score)
            
            return ("", 0)
            
        except Exception as e:
            return ("", 0)
    
    @staticmethod
    def _score_quality(text: str) -> float:
        """
        Score OCR result quality
        Higher score = better quality
        
        Args:
            text: Extracted text
        
        Returns:
            Quality score (higher is better)
        """
        score = 0
        
        # Length score (longer is usually better, up to a point)
        length = len(text.strip())
        score += min(length, 1000) / 10
        
        # Word count
        words = text.split()
        score += len(words) * 2
        
        # Receipt/bill keywords (indicates relevant content)
        keywords = [
            'total', 'date', 'amount', 'receipt', 'bill', 'invoice',
            'tax', 'subtotal', 'change', 'cash', 'payment', 'price'
        ]
        for kw in keywords:
            if kw.lower() in text.lower():
                score += 10
        
        # Presence of numbers (receipts have many numbers)
        numbers = re.findall(r'\d+\.?\d*', text)
        score += len(numbers) * 3
        
        # Date patterns (common in receipts)
        if re.search(r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}', text):
            score += 20
        
        # Currency symbols
        if re.search(r'Rs\.?|LKR|\$|₹', text):
            score += 15
        
        # Penalty for excessive special characters (indicates OCR noise)
        special = len(re.findall(r'[^a-zA-Z0-9\s\.,:\-/()]', text))
        score -= special * 0.5
        
        return max(0, score)

# ============================================================================
# REALTIME OCR (FOR READER MODE)
# ============================================================================

class RealtimeOCR:
    """Optimized OCR for real-time text detection and reading"""
    
    @staticmethod
    def quick_extract(image_bytes: bytes, mode: str = 'fast') -> str:
        """
        Fast extraction for real-time applications
        
        Args:
            image_bytes: Raw image bytes
            mode: 'fast' or 'full'
        
        Returns:
            Extracted text
        """
        try:
            # Decode
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if img is None:
                return ""
            
            # Quick resize if too large (for performance)
            height, width = img.shape[:2]
            max_width = OCR_CONFIG.get('max_width', 1024)
            
            if width > max_width:
                scale = max_width / width
                img = cv2.resize(img, None, fx=scale, fy=scale, 
                               interpolation=cv2.INTER_AREA)
            
            # Quick binarization
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            _, binary = cv2.threshold(gray, 0, 255, 
                                     cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            
            # Check if inversion needed (white text on black background)
            num_white = cv2.countNonZero(binary)
            if num_white < binary.size / 2:
                binary = cv2.bitwise_not(binary)
            
            # Extract with appropriate PSM
            psm = 6 if mode == 'full' else 3
            config = f'--psm {psm} --oem 3'
            text = pytesseract.image_to_string(binary, config=config)
            
            return RealtimeOCR._clean_text(text)
            
        except Exception as e:
            print(f"[REALTIME OCR ERROR] {e}")
            return ""
    
    @staticmethod
    def detect_regions(image_bytes: bytes) -> List[Dict]:
        """
        Detect text regions with bounding boxes
        
        Args:
            image_bytes: Raw image bytes
        
        Returns:
            List of dicts with 'text' and 'bbox' keys
        """
        try:
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if img is None:
                return []
            
            # Quick preprocessing
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            _, binary = cv2.threshold(gray, 0, 255, 
                                     cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            
            # Detect with pytesseract
            config = '--psm 3 --oem 3'
            data = pytesseract.image_to_data(
                binary,
                config=config,
                output_type=pytesseract.Output.DICT
            )
            
            # Extract regions
            regions = []
            n_boxes = len(data['text'])
            
            for i in range(n_boxes):
                text = data['text'][i].strip()
                conf = int(data['conf'][i])
                
                if conf > OCR_CONFIG['confidence_threshold'] and len(text) > 1:
                    x = data['left'][i]
                    y = data['top'][i]
                    w = data['width'][i]
                    h = data['height'][i]
                    
                    regions.append({
                        'text': text,
                        'bbox': (x, y, w, h),
                        'confidence': conf
                    })
            
            return regions
            
        except Exception as e:
            print(f"[REALTIME OCR ERROR] {e}")
            return []
    
    @staticmethod
    def _clean_text(text: str) -> str:
        """
        Clean OCR output for natural reading
        
        Args:
            text: Raw OCR text
        
        Returns:
            Cleaned text
        """
        if not text:
            return ""
        
        # Normalize whitespace
        text = ' '.join(text.split())
        
        # Remove isolated special characters
        text = re.sub(r'\b[^\w\s]\b', '', text)
        
        # Common OCR error corrections
        replacements = {
            '|': 'I',
            '\n\n\n': '\n'
        }
        
        for old, new in replacements.items():
            text = text.replace(old, new)
        
        return text.strip()
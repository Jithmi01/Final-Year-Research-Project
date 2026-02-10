# ============================================================================
# FILE: app/services/document_reading_service.py
# Document Reading System - IMPROVED VERSION with Better OCR
# ============================================================================

import cv2
import numpy as np
from typing import Dict, List, Optional, Tuple
from datetime import datetime
import re
from collections import deque
from difflib import SequenceMatcher

# Import OCR engines
try:
    from paddleocr import PaddleOCR
    PADDLE_AVAILABLE = True
except ImportError:
    PADDLE_AVAILABLE = False
    print("[PADDLE OCR] ✗ Not installed")

try:
    import pytesseract
    TESSERACT_AVAILABLE = True
except ImportError:
    TESSERACT_AVAILABLE = False
    print("[TESSERACT] ✗ Not installed")


class OCRService:
    """
    Unified OCR service with automatic fallback
    """
    
    def __init__(self):
        """Initialize OCR engines"""
        self.paddle_ocr = None
        self.use_paddle = False
        
        # Try PaddleOCR first (better accuracy)
        if PADDLE_AVAILABLE:
            try:
                # ✅ FIX: Correct PaddleOCR parameters
                self.paddle_ocr = PaddleOCR(
                    use_angle_cls=True,
                    lang='en'
                    # Removed use_gpu parameter - let PaddleOCR decide automatically
                )
                self.use_paddle = True
                print("[PADDLE OCR] ✓ Initialized successfully")
            except Exception as e:
                print(f"[PADDLE OCR] ✗ Failed: {e}")
                self.use_paddle = False
        
        # Fallback to Tesseract
        if not self.use_paddle and TESSERACT_AVAILABLE:
            print("[TESSERACT OCR] ✓ Using as primary engine")
        
        if not self.use_paddle and not TESSERACT_AVAILABLE:
            raise RuntimeError("No OCR engine available! Install PaddleOCR or Tesseract")
    
    def extract_text_from_roi(self, image, region_type='document'):
        """
        Extract text from image with automatic engine selection
        
        Args:
            image: OpenCV image (numpy array)
            region_type: Type of region ('document', 'currency', etc.)
        
        Returns:
            str: Extracted text
        """
        try:
            # Try PaddleOCR first
            if self.use_paddle and self.paddle_ocr:
                try:
                    result = self.paddle_ocr.ocr(image, cls=True)
                    if result and result[0]:
                        # Extract text from PaddleOCR result
                        text_lines = []
                        for line in result[0]:
                            if line[1][0]:  # line[1][0] is the text
                                text_lines.append(line[1][0])
                        
                        extracted = '\n'.join(text_lines)
                        print(f"[PADDLE OCR] ✓ Extracted {len(text_lines)} lines, {len(extracted)} chars")
                        return extracted
                except Exception as e:
                    print(f"[PADDLE OCR] Error: {e}")
                    # Fallback to Tesseract
            
            # Use Tesseract with better configuration
            if TESSERACT_AVAILABLE:
                # ✅ IMPROVED: Use better Tesseract config for documents
                custom_config = r'--oem 3 --psm 6'  # PSM 6 = assume uniform block of text
                extracted = pytesseract.image_to_string(image, config=custom_config)
                print(f"[TESSERACT OCR] ✓ Extracted {len(extracted)} characters")
                return extracted
            
            return ""
        
        except Exception as e:
            print(f"[OCR ERROR] {e}")
            import traceback
            traceback.print_exc()
            return ""


class DocumentReader:
    """
    Real-time document reading with continuous OCR and intelligent text tracking
    """
    
    def __init__(self):
        """Initialize document reader"""
        self.ocr = OCRService()
        
        # Text tracking for continuous reading
        self.previous_text = deque(maxlen=10)  # Store last 10 frames
        self.similarity_threshold = 0.85  # 85% similarity = same text
        self.last_spoken_text = ""
        self.last_spoken_time = None
        self.repeat_delay = 3.0  # Don't repeat same text within 3 seconds
        
        # Document state
        self.captured_document = None
        self.document_metadata = {}
        
        print("[DOCUMENT READER] ✓ Initialized")
    
    def read_continuous(self, image_bytes: bytes) -> Dict:
        """
        Continuous reading mode - extract and identify new text
        """
        print("[CONTINUOUS READ] Processing image...")
        try:
            # Decode image
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                print("[CONTINUOUS READ] ✗ Cannot decode image")
                return self._create_error_result("Cannot read image")
            
            print(f"[CONTINUOUS READ] Image size: {image.shape}")
            
            # ✅ IMPROVED: Use original image for OCR instead of aggressive enhancement
            # Just convert to grayscale - no threshold
            if len(image.shape) == 3:
                gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            else:
                gray = image
            
            print("[CONTINUOUS READ] Image prepared for OCR")
            
            # Extract text using OCR
            ocr_result = self.ocr.extract_text_from_roi(gray, 'document')
            print(f"[CONTINUOUS READ] Raw OCR: '{ocr_result[:100] if ocr_result else '(empty)'}'...")
            
            if not ocr_result or len(ocr_result.strip()) < 3:
                print("[CONTINUOUS READ] No significant text detected")
                return {
                    'success': True,
                    'text': '',
                    'new_text': '',
                    'should_speak': False,
                    'confidence': 0.0,
                    'regions': 0,
                    'voice_prompt': ''
                }
            
            # Clean extracted text
            current_text = self._clean_text(ocr_result)
            print(f"[CONTINUOUS READ] Cleaned text: '{current_text[:150]}'...")
            
            # Check if this is new text
            is_new = self._is_new_text(current_text)
            print(f"[CONTINUOUS READ] Is new: {is_new}")
            
            # Update tracking
            self.previous_text.append(current_text)
            
            if is_new:
                self.last_spoken_text = current_text
                self.last_spoken_time = datetime.now()
                
                print(f"[CONTINUOUS READ] ✓ New text to speak!")
                
                return {
                    'success': True,
                    'text': current_text,
                    'new_text': current_text,
                    'should_speak': True,
                    'confidence': 0.95,
                    'regions': len(current_text.split('\n')),
                    'voice_prompt': current_text
                }
            else:
                print("[CONTINUOUS READ] Skipping (duplicate)")
                return {
                    'success': True,
                    'text': current_text,
                    'new_text': '',
                    'should_speak': False,
                    'confidence': 0.95,
                    'regions': len(current_text.split('\n')),
                    'voice_prompt': ''
                }
        
        except Exception as e:
            print(f"[CONTINUOUS READ ERROR] {e}")
            import traceback
            traceback.print_exc()
            return self._create_error_result(str(e))
    
    def capture_document(self, image_bytes: bytes) -> Dict:
        """
        Capture mode - Save document for detailed analysis and Q&A
        """
        print("[CAPTURE] Processing document...")
        try:
            # Decode image
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                print("[CAPTURE] ✗ Cannot decode image")
                return self._create_error_result("Cannot read image")
            
            print(f"[CAPTURE] Image size: {image.shape}")
            
            # Convert to grayscale
            if len(image.shape) == 3:
                gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            else:
                gray = image
            
            # Extract comprehensive text
            full_text = self.ocr.extract_text_from_roi(gray, 'document')
            
            print(f"[CAPTURE] Extracted {len(full_text) if full_text else 0} characters")
            
            if not full_text or len(full_text.strip()) < 5:
                print("[CAPTURE] ✗ No significant text detected")
                return {
                    'success': False,
                    'error': 'No text detected in document',
                    'voice_prompt': 'No text found. Try better lighting or move closer.'
                }
            
            # Clean and process text
            cleaned_text = self._clean_text(full_text)
            lines = [line.strip() for line in cleaned_text.split('\n') if line.strip()]
            
            print(f"[CAPTURE] Cleaned into {len(lines)} lines")
            
            # Extract metadata
            metadata = self._extract_metadata(cleaned_text)
            
            # Generate document ID
            doc_id = f"doc_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            
            # Store document
            self.captured_document = {
                'id': doc_id,
                'text': cleaned_text,
                'lines': lines,
                'metadata': metadata,
                'captured_at': datetime.now().isoformat()
            }
            self.document_metadata = metadata
            
            print(f"[CAPTURE] ✓ Document saved: {doc_id}")
            
            # Create voice prompt
            line_count = len(lines)
            word_count = len(cleaned_text.split())
            voice_prompt = f"Document captured. {line_count} lines, {word_count} words. Ready for questions."
            
            return {
                'success': True,
                'document_id': doc_id,
                'text': cleaned_text,
                'lines': lines,
                'metadata': metadata,
                'voice_prompt': voice_prompt
            }
        
        except Exception as e:
            print(f"[CAPTURE ERROR] {e}")
            import traceback
            traceback.print_exc()
            return self._create_error_result(str(e))
    
    def answer_question(self, question: str) -> Dict:
        """Answer questions about captured document"""
        print(f"[Q&A] Question: {question}")
        
        if not self.captured_document:
            print("[Q&A] ✗ No document captured")
            return {
                'success': False,
                'error': 'No document captured. Please capture a document first.',
                'answer': '',
                'confidence': 0.0,
                'voice_prompt': 'Please capture a document first.'
            }
        
        try:
            text = self.captured_document['text']
            lines = self.captured_document['lines']
            metadata = self.captured_document['metadata']
            
            question_lower = question.lower().strip()
            
            # Question type detection
            answer = ""
            confidence = 0.0
            
            # 1. Amount/Money questions
            if any(word in question_lower for word in ['amount', 'total', 'cost', 'price', 'pay', 'money', 'dollar']):
                if metadata.get('amounts'):
                    amounts = metadata['amounts']
                    answer = f"Found amounts: {', '.join(amounts)}"
                    confidence = 0.9
                else:
                    answer = "No amounts found in this document"
                    confidence = 0.5
            
            # 2. Date questions
            elif any(word in question_lower for word in ['date', 'when', 'day']):
                if metadata.get('dates'):
                    dates = metadata['dates']
                    answer = f"Found dates: {', '.join(dates)}"
                    confidence = 0.9
                else:
                    answer = "No dates found in this document"
                    confidence = 0.5
            
            # 3. Contact information
            elif any(word in question_lower for word in ['email', 'contact', 'phone', 'number']):
                contacts = []
                if metadata.get('emails'):
                    contacts.extend([f"Email: {e}" for e in metadata['emails']])
                if metadata.get('phones'):
                    contacts.extend([f"Phone: {p}" for p in metadata['phones']])
                
                if contacts:
                    answer = ', '.join(contacts)
                    confidence = 0.9
                else:
                    answer = "No contact information found"
                    confidence = 0.5
            
            # 4. Line-specific reading
            elif 'line' in question_lower and any(char.isdigit() for char in question):
                line_num = int(''.join(filter(str.isdigit, question)))
                if 1 <= line_num <= len(lines):
                    answer = lines[line_num - 1]
                    confidence = 1.0
                else:
                    answer = f"Line {line_num} not found. Document has {len(lines)} lines."
                    confidence = 0.5
            
            # 5. Read all / full text
            elif any(phrase in question_lower for phrase in ['read all', 'read everything', 'full text', 'entire document']):
                answer = text
                confidence = 1.0
            
            # 6. Keyword search
            else:
                keywords = [word for word in question_lower.split() if len(word) > 3]
                matching_lines = []
                
                for line in lines:
                    if any(keyword in line.lower() for keyword in keywords):
                        matching_lines.append(line)
                
                if matching_lines:
                    answer = '\n'.join(matching_lines[:3])
                    confidence = 0.7
                else:
                    answer = "I couldn't find specific information about that in the document."
                    confidence = 0.3
            
            print(f"[Q&A] Answer: {answer[:100]}...")
            
            return {
                'success': True,
                'answer': answer,
                'confidence': confidence,
                'voice_prompt': answer if answer else "No answer found"
            }
        
        except Exception as e:
            print(f"[Q&A ERROR] {e}")
            import traceback
            traceback.print_exc()
            return self._create_error_result(str(e))
    
    def get_current_document(self) -> Optional[Dict]:
        """Get currently captured document"""
        return self.captured_document
    
    def clear_document(self):
        """Clear captured document"""
        self.captured_document = None
        self.document_metadata = {}
        print("[DOCUMENT READER] Document cleared")
    
    # ========== Helper Methods ==========
    
    def _clean_text(self, text: str) -> str:
        """Clean OCR-extracted text"""
        if not text:
            return ""
        
        # Remove excessive whitespace but keep line breaks
        lines = text.split('\n')
        cleaned_lines = [' '.join(line.split()) for line in lines]
        cleaned = '\n'.join(cleaned_lines)
        
        # Remove empty lines
        cleaned = '\n'.join(line for line in cleaned.split('\n') if line.strip())
        
        return cleaned.strip()
    
    def _is_new_text(self, current_text: str) -> bool:
        """Check if current text is significantly different from previous"""
        if not current_text or len(current_text) < 3:
            return False
        
        # Check against last spoken text with time delay
        if self.last_spoken_time:
            time_since_last = (datetime.now() - self.last_spoken_time).total_seconds()
            if time_since_last < self.repeat_delay:
                similarity = self._text_similarity(current_text, self.last_spoken_text)
                if similarity > self.similarity_threshold:
                    return False
        
        # Check against recent previous texts
        for prev_text in self.previous_text:
            similarity = self._text_similarity(current_text, prev_text)
            if similarity > self.similarity_threshold:
                return False
        
        return True
    
    def _text_similarity(self, text1: str, text2: str) -> float:
        """Calculate similarity between two texts (0-1)"""
        if not text1 or not text2:
            return 0.0
        
        return SequenceMatcher(None, text1.lower(), text2.lower()).ratio()
    
    def _extract_metadata(self, text: str) -> Dict:
        """Extract structured metadata from text"""
        metadata = {
            'dates': [],
            'amounts': [],
            'emails': [],
            'phones': []
        }
        
        # Extract dates
        date_patterns = [
            r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}',
            r'\d{4}[/-]\d{1,2}[/-]\d{1,2}',
            r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2},? \d{4}'
        ]
        for pattern in date_patterns:
            metadata['dates'].extend(re.findall(pattern, text, re.IGNORECASE))
        
        # Extract amounts
        amount_pattern = r'[$€£¥]\s*\d+(?:,\d{3})*(?:\.\d{2})?'
        metadata['amounts'].extend(re.findall(amount_pattern, text))
        
        # Extract emails
        email_pattern = r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
        metadata['emails'].extend(re.findall(email_pattern, text))
        
        # Extract phone numbers
        phone_pattern = r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}'
        metadata['phones'].extend(re.findall(phone_pattern, text))
        
        return metadata
    
    def _create_error_result(self, error_message: str) -> Dict:
        """Create standardized error result"""
        return {
            'success': False,
            'error': error_message,
            'text': '',
            'new_text': '',
            'should_speak': False,
            'confidence': 0.0,
            'regions': 0,
            'voice_prompt': f"Error: {error_message}"
        }


# ============================================================================
# GLOBAL INSTANCE MANAGEMENT
# ============================================================================

_document_reader_instance = None

def get_document_reader():
    """Get or create the global DocumentReader instance"""
    global _document_reader_instance
    if _document_reader_instance is None:
        _document_reader_instance = DocumentReader()
        print("[DOCUMENT READER] ✓ Singleton instance created")
    return _document_reader_instance
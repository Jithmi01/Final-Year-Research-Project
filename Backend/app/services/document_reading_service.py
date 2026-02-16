# ============================================================================
# FILE: app/services/document_reading_service.py
# FAST VERSION - Tesseract Only (No PaddleOCR delays)
# ============================================================================

import cv2
import numpy as np
from typing import Dict, List, Optional
from datetime import datetime
import re
from collections import deque
from difflib import SequenceMatcher

# Use Tesseract only for speed
try:
    import pytesseract
    TESSERACT_AVAILABLE = True
    print("[TESSERACT OCR] ✓ Available")
except ImportError:
    TESSERACT_AVAILABLE = False
    print("[TESSERACT] ✗ Not installed")
    raise RuntimeError("Tesseract required! Install: pip install pytesseract")


class DocumentReader:
    """
    FAST document reader - Tesseract only, no model loading delays
    """
    
    def __init__(self):
        """Initialize document reader"""
        # Text tracking
        self.previous_text = deque(maxlen=10)
        self.similarity_threshold = 0.85
        self.last_spoken_text = ""
        self.last_spoken_time = None
        self.repeat_delay = 3.0
        
        # Document state
        self.captured_document = None
        self.document_metadata = {}
        
        print("[DOCUMENT READER] ✓ FAST MODE - Tesseract only")
    
    def read_continuous(self, image_bytes: bytes) -> Dict:
        """Fast continuous reading"""
        try:
            # Decode image
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                return self._create_error_result("Cannot read image")
            
            # Convert to grayscale (simple, fast)
            if len(image.shape) == 3:
                gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            else:
                gray = image
            
            # ⚡ FAST OCR - Tesseract with optimized settings
            ocr_result = pytesseract.image_to_string(
                gray,
                config='--oem 3 --psm 6'  # Fast mode
            )
            
            if not ocr_result or len(ocr_result.strip()) < 3:
                return {
                    'success': True,
                    'text': '',
                    'new_text': '',
                    'should_speak': False,
                    'confidence': 0.0,
                    'regions': 0,
                    'voice_prompt': ''
                }
            
            # Clean text
            current_text = self._clean_text(ocr_result)
            
            # Check if new
            is_new = self._is_new_text(current_text)
            
            # Update tracking
            self.previous_text.append(current_text)
            
            if is_new:
                self.last_spoken_text = current_text
                self.last_spoken_time = datetime.now()
                
                print(f"[FAST READ] ✓ New: {current_text[:50]}...")
                
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
                return {
                    'success': True,
                    'text': current_text,
                    'new_text': '',
                    'should_speak': False,
                    'confidence': 0.95,
                    'regions': 0,
                    'voice_prompt': ''
                }
        
        except Exception as e:
            print(f"[READ ERROR] {e}")
            return self._create_error_result(str(e))
    
    def capture_document(self, image_bytes: bytes) -> Dict:
        """Fast document capture"""
        try:
            # Decode
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                return self._create_error_result("Cannot read image")
            
            # Grayscale
            if len(image.shape) == 3:
                gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            else:
                gray = image
            
            # ⚡ FAST OCR
            full_text = pytesseract.image_to_string(gray, config='--oem 3 --psm 6')
            
            if not full_text or len(full_text.strip()) < 5:
                return {
                    'success': False,
                    'error': 'No text detected',
                    'voice_prompt': 'No text found. Try better lighting.'
                }
            
            # Clean and process
            cleaned_text = self._clean_text(full_text)
            lines = [line.strip() for line in cleaned_text.split('\n') if line.strip()]
            metadata = self._extract_metadata(cleaned_text)
            
            # Store
            doc_id = f"doc_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            self.captured_document = {
                'id': doc_id,
                'text': cleaned_text,
                'lines': lines,
                'metadata': metadata,
                'captured_at': datetime.now().isoformat()
            }
            
            print(f"[CAPTURE] ✓ {len(lines)} lines")
            
            return {
                'success': True,
                'document_id': doc_id,
                'text': cleaned_text,
                'lines': lines,
                'metadata': metadata,
                'voice_prompt': f"Document captured. {len(lines)} lines. Ready for questions."
            }
        
        except Exception as e:
            print(f"[CAPTURE ERROR] {e}")
            return self._create_error_result(str(e))
    
    def answer_question(self, question: str) -> Dict:
        """Answer questions"""
        if not self.captured_document:
            return {
                'success': False,
                'error': 'No document captured',
                'answer': '',
                'confidence': 0.0,
                'voice_prompt': 'Please capture a document first.'
            }
        
        try:
            text = self.captured_document['text']
            lines = self.captured_document['lines']
            metadata = self.captured_document['metadata']
            
            q = question.lower().strip()
            answer = ""
            confidence = 0.0
            
            # Amount
            if any(w in q for w in ['amount', 'total', 'cost', 'price', 'money', 'dollar']):
                if metadata.get('amounts'):
                    answer = f"Found amounts: {', '.join(metadata['amounts'])}"
                    confidence = 0.9
                else:
                    answer = "No amounts found"
                    confidence = 0.5
            
            # Date
            elif any(w in q for w in ['date', 'when', 'day']):
                if metadata.get('dates'):
                    answer = f"Found dates: {', '.join(metadata['dates'])}"
                    confidence = 0.9
                else:
                    answer = "No dates found"
                    confidence = 0.5
            
            # Contact
            elif any(w in q for w in ['email', 'contact', 'phone', 'number']):
                contacts = []
                if metadata.get('emails'):
                    contacts.extend([f"Email: {e}" for e in metadata['emails']])
                if metadata.get('phones'):
                    contacts.extend([f"Phone: {p}" for p in metadata['phones']])
                
                if contacts:
                    answer = ', '.join(contacts)
                    confidence = 0.9
                else:
                    answer = "No contact info found"
                    confidence = 0.5
            
            # Line number
            elif 'line' in q and any(c.isdigit() for c in question):
                line_num = int(''.join(filter(str.isdigit, question)))
                if 1 <= line_num <= len(lines):
                    answer = lines[line_num - 1]
                    confidence = 1.0
                else:
                    answer = f"Line {line_num} not found. Has {len(lines)} lines."
                    confidence = 0.5
            
            # Read all
            elif any(p in q for p in ['read all', 'everything', 'full text', 'entire']):
                answer = text
                confidence = 1.0
            
            # Keyword search
            else:
                keywords = [w for w in q.split() if len(w) > 3]
                matches = [line for line in lines if any(k in line.lower() for k in keywords)]
                
                if matches:
                    answer = '\n'.join(matches[:3])
                    confidence = 0.7
                else:
                    answer = "Couldn't find that information."
                    confidence = 0.3
            
            return {
                'success': True,
                'answer': answer,
                'confidence': confidence,
                'voice_prompt': answer if answer else "No answer found"
            }
        
        except Exception as e:
            print(f"[Q&A ERROR] {e}")
            return self._create_error_result(str(e))
    
    def get_current_document(self) -> Optional[Dict]:
        return self.captured_document
    
    def clear_document(self):
        self.captured_document = None
        self.document_metadata = {}
    
    # ========== Helpers ==========
    
    def _clean_text(self, text: str) -> str:
        if not text:
            return ""
        lines = text.split('\n')
        cleaned_lines = [' '.join(line.split()) for line in lines]
        cleaned = '\n'.join(line for line in cleaned_lines if line.strip())
        return cleaned.strip()
    
    def _is_new_text(self, current_text: str) -> bool:
        if not current_text or len(current_text) < 3:
            return False
        
        # Time check
        if self.last_spoken_time:
            time_diff = (datetime.now() - self.last_spoken_time).total_seconds()
            if time_diff < self.repeat_delay:
                similarity = SequenceMatcher(None, current_text.lower(), 
                                            self.last_spoken_text.lower()).ratio()
                if similarity > self.similarity_threshold:
                    return False
        
        # Previous text check
        for prev in self.previous_text:
            similarity = SequenceMatcher(None, current_text.lower(), 
                                        prev.lower()).ratio()
            if similarity > self.similarity_threshold:
                return False
        
        return True
    
    def _extract_metadata(self, text: str) -> Dict:
        metadata = {'dates': [], 'amounts': [], 'emails': [], 'phones': []}
        
        # Dates
        date_patterns = [
            r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}',
            r'\d{4}[/-]\d{1,2}[/-]\d{1,2}',
            r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2},? \d{4}'
        ]
        for pattern in date_patterns:
            metadata['dates'].extend(re.findall(pattern, text, re.IGNORECASE))
        
        # Amounts
        metadata['amounts'].extend(re.findall(r'[$€£¥]\s*\d+(?:,\d{3})*(?:\.\d{2})?', text))
        
        # Emails
        metadata['emails'].extend(re.findall(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', text))
        
        # Phones
        metadata['phones'].extend(re.findall(r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}', text))
        
        return metadata
    
    def _create_error_result(self, error_message: str) -> Dict:
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
# SINGLETON
# ============================================================================

_document_reader_instance = None

def get_document_reader():
    global _document_reader_instance
    if _document_reader_instance is None:
        _document_reader_instance = DocumentReader()
        print("[DOCUMENT READER] ✓ Singleton created")
    return _document_reader_instance
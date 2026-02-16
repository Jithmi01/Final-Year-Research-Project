# FILE: services/integrated_face_service.py
# FIXED VERSION - Integrated face detection combining recognition, age/gender, and attributes

import cv2
import numpy as np
import os
from services.face_recognition_service import FaceRecognitionService
from services.age_gender_service import AgeGenderService
from services.attributes_service import AttributesService
from config import Config
import logging

logger = logging.getLogger(__name__)

class IntegratedFaceService:
    """
    Unified face detection service for blind users.
    Combines face recognition, age/gender detection, and attribute detection.
    """
    
    def __init__(self, mongodb_uri=None):
        logger.info("Initializing Integrated Face Service...")
        
        # Initialize all three services
        self.face_recognition = FaceRecognitionService(mongodb_uri)
        self.age_gender = AgeGenderService()
        self.attributes = AttributesService()
        
        # Face detection cascade (for quick face detection)
        self.face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        )
        
        logger.info("✓ Integrated Face Service ready")
    
    def detect_face_in_frame(self, image_path):
        """
        Quick face detection for voice feedback.
        Returns True if face detected, False otherwise.
        """
        try:
            image = cv2.imread(image_path)
            if image is None:
                logger.error(f"Failed to read image: {image_path}")
                return False
            
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            faces = self.face_cascade.detectMultiScale(
                gray, 
                scaleFactor=1.1, 
                minNeighbors=5, 
                minSize=(60, 60)
            )
            
            detected = len(faces) > 0
            logger.info(f"Quick face detection: {detected} (found {len(faces)} faces)")
            return detected
            
        except Exception as e:
            logger.error(f"Face detection error: {e}")
            return False
    
    def analyze_face(self, image_path):
        """
        Complete face analysis for blind users.
        
        FIXED WORKFLOW:
        1. Verify image exists and is readable
        2. Try face recognition first (which has its own detection)
        3. If recognition succeeds with known person → return recognition data
        4. If recognition fails OR returns unknown → try age/gender + attributes
        5. Always return face position and distance when available
        
        Returns:
        {
            'face_detected': bool,
            'person_type': 'known' | 'unknown',
            'announcement': str,  # Voice output text
            'data': {}  # All detection results
        }
        """
        try:
            # Step 0: Verify image exists
            if not os.path.exists(image_path):
                logger.error(f"Image file does not exist: {image_path}")
                return {
                    'face_detected': False,
                    'error': 'Image file not found',
                    'announcement': 'Error: Image file not found. Please try again.'
                }
            
            # Step 1: Try face recognition first
            # The face recognition service should handle its own face detection
            logger.info("Starting face recognition attempt...")
            recognition_result = self.face_recognition.recognize_from_image(image_path)
            
            logger.info(f"Recognition result: {recognition_result}")
            
            # Step 2: Check if recognition found a known person
            # We need to check multiple conditions:
            # - 'name' exists and is not 'Unknown'
            # - OR 'recognized' is True
            # - Face was actually detected
            
            is_known_person = False
            face_was_detected = False
            
            # Check if face was detected during recognition
            if 'error' not in recognition_result:
                face_was_detected = True
                
                # Check if it's a known person
                if 'name' in recognition_result:
                    person_name = recognition_result['name']
                    if person_name and person_name != 'Unknown' and person_name.strip() != '':
                        is_known_person = True
                        logger.info(f"✓ Known person detected: {person_name}")
            
            # Step 3: Handle known person
            if is_known_person:
                announcement = self._build_known_person_announcement(recognition_result)
                
                return {
                    'face_detected': True,
                    'person_type': 'known',
                    'announcement': announcement,
                    'data': {
                        'recognition': recognition_result,
                        'name': recognition_result.get('name', 'Unknown'),
                        'confidence': recognition_result.get('confidence', 0),
                        'distance_m': recognition_result.get('distance_m', 'unknown'),
                        'position': recognition_result.get('position', 'center'),
                        'last_seen': recognition_result.get('last_seen')
                    }
                }
            
            # Step 4: Handle unknown person or no face detected
            # If face was detected but not recognized, or if we need to verify face exists
            logger.info("Checking if face exists in frame...")
            
            # Double-check with our own face detection
            has_face = self.detect_face_in_frame(image_path)
            
            if not has_face and not face_was_detected:
                logger.warning("No face detected in image")
                return {
                    'face_detected': False,
                    'error': 'No face detected',
                    'announcement': 'No face detected. Please position the camera to show a person\'s face clearly and try again.'
                }
            
            # Step 5: Face exists but unknown - get age/gender + attributes
            logger.info("Unknown person detected - analyzing age, gender, and attributes...")
            
            age_gender_result = self.age_gender.detect_from_image(image_path)
            attributes_result = self.attributes.detect_from_image(image_path)
            
            # Extract distance and position from recognition result
            # Even if person is unknown, recognition might have calculated these
            distance = recognition_result.get('distance_m', 'unknown')
            position = recognition_result.get('position', 'center')
            
            logger.info(f"Age/Gender result: {age_gender_result}")
            logger.info(f"Attributes result: {attributes_result}")
            
            announcement = self._build_unknown_person_announcement(
                age_gender_result,
                attributes_result,
                distance,
                position
            )
            
            return {
                'face_detected': True,
                'person_type': 'unknown',
                'announcement': announcement,
                'data': {
                    'age_gender': age_gender_result,
                    'attributes': attributes_result,
                    'distance_m': distance,
                    'position': position
                }
            }
            
        except Exception as e:
            logger.error(f"Analysis error: {e}", exc_info=True)
            return {
                'face_detected': False,
                'error': str(e),
                'announcement': 'Error analyzing face. Please try again.'
            }
    
    def _build_known_person_announcement(self, recognition_data):
        """
        Build voice announcement for known person.
        Format: "[Name] detected from your [position], [distance] meters away. Last seen on [date time]"
        """
        name = recognition_data.get('name', 'Unknown')
        position = recognition_data.get('position', 'center')
        distance = recognition_data.get('distance_m', 'unknown')
        last_seen = recognition_data.get('last_seen')
        
        announcement = f"{name} detected"
        
        # Add position
        if position and position != 'center':
            announcement += f" from your {position}"
        
        # Add distance
        if distance != 'unknown' and distance is not None:
            try:
                distance_str = f"{float(distance):.1f}" if isinstance(distance, (int, float)) else str(distance)
                announcement += f", approximately {distance_str} meters away"
            except:
                pass
        
        # Add last seen
        if last_seen:
            announcement += f". Last seen on {last_seen}"
        else:
            announcement += ". First time detected"
        
        logger.info(f"Known person announcement: {announcement}")
        return announcement
    
    def _build_unknown_person_announcement(self, age_gender_data, attributes_data, distance, position):
        """
        Build voice announcement for unknown person.
        Format: "Unknown person detected from your [position], [distance] meters away. 
                [Gender], about [age group]. [Attributes description]"
        """
        # Base announcement
        announcement = "Unknown person detected"
        
        # Add position (only if not center)
        if position and position != 'center':
            announcement += f" from your {position}"
        
        # Add distance
        if distance != 'unknown' and distance is not None:
            try:
                distance_str = f"{float(distance):.1f}" if isinstance(distance, (int, float)) else str(distance)
                announcement += f", approximately {distance_str} meters away"
            except:
                pass
        
        # Add age and gender
        if age_gender_data and not age_gender_data.get('error'):
            gender = age_gender_data.get('gender', '').lower()
            age_group = age_gender_data.get('age_group', '')
            
            if gender:
                announcement += f". Appears to be {gender}"
                
                if age_group:
                    announcement += f", about {age_group}"
        
        # Add attributes
        if attributes_data and not attributes_data.get('error'):
            attributes = attributes_data.get('attributes', {})
            wearing = attributes.get('wearing', [])
            having = attributes.get('having', [])
            
            attribute_parts = []
            
            if wearing:
                wearing_str = ', '.join(wearing)
                attribute_parts.append(f"wearing {wearing_str}")
            
            if having:
                having_str = ', '.join(having)
                attribute_parts.append(f"has {having_str}")
            
            if attribute_parts:
                announcement += ". Person is " + " and ".join(attribute_parts)
        
        logger.info(f"Unknown person announcement: {announcement}")
        return announcement
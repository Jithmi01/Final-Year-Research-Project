import os
import cv2
import numpy as np
import pickle
import time
from pathlib import Path
from pymongo import MongoClient
import torch
from facenet_pytorch import MTCNN, InceptionResnetV1
from config import Config
from datetime import datetime
from bson import ObjectId

class FaceRecognitionService:
    def __init__(self, mongodb_uri=None):
        self.known_faces_dir = Config.KNOWN_FACES_DIR
        self.embeddings_dir = Config.EMBEDDINGS_DIR
        self.known_embeddings = {}
        self.threshold = Config.FACE_RECOGNITION_THRESHOLD
        self.detection_cooldown = Config.DETECTION_COOLDOWN
        self.last_detection = {}  # timestamp of last detection
        self.last_seen_time = {}  # formatted last seen
        self.last_seen_file = os.path.join(self.embeddings_dir, "last_seen.pkl")
        self.registration_metadata = {}  # Store registration dates
        self.metadata_file = os.path.join(self.embeddings_dir, "metadata.pkl")

        # Camera calibration for distance
        self.KNOWN_FACE_WIDTH = 0.16  # meters, average adult face width
        self.FOCAL_LENGTH = Config.FOCAL_LENGTH  # calibrated for your camera

        # Models
        self.device = torch.device('cuda:0' if torch.cuda.is_available() else 'cpu')
        self.mtcnn = MTCNN(image_size=160, margin=0, device=self.device, keep_all=False)
        self.resnet = InceptionResnetV1(pretrained='vggface2').eval().to(self.device)

        # MongoDB
        if mongodb_uri:
            self.mongo_client = MongoClient(mongodb_uri)
            self.db = self.mongo_client[Config.MONGODB_DB_NAME]
            self.faces_collection = self.db['known_faces']
        else:
            self.mongo_client = None

        Path(self.known_faces_dir).mkdir(parents=True, exist_ok=True)
        Path(self.embeddings_dir).mkdir(parents=True, exist_ok=True)

        self.load_embeddings()
        self.load_last_seen()
        self.load_metadata()

    # --- Face Embedding ---
    def extract_face_embedding(self, image):
        image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        face = self.mtcnn(image_rgb)
        if face is None:
            return None
        face = face.unsqueeze(0).to(self.device)
        with torch.no_grad():
            embedding = self.resnet(face).cpu().numpy()[0]
        return embedding / np.linalg.norm(embedding)

    # --- Register Person ---
    def register_person(self, name, image_paths):
        embeddings_list = []
        for img_path in image_paths:
            image = cv2.imread(img_path)
            emb = self.extract_face_embedding(image)
            if emb is not None:
                embeddings_list.append(emb)
                person_dir = os.path.join(self.known_faces_dir, name)
                Path(person_dir).mkdir(exist_ok=True)
                cv2.imwrite(os.path.join(person_dir, os.path.basename(img_path)), image)
        
        if embeddings_list:
            # Store registration metadata
            registration_date = datetime.now()
            self.registration_metadata[name] = {
                'date': registration_date.strftime("%Y-%m-%d"),
                'time': registration_date.strftime("%I:%M %p"),
                'datetime': registration_date.strftime("%Y-%m-%d %I:%M %p"),
                'timestamp': registration_date.timestamp()
            }
            
            self.known_embeddings[name] = {
                "embeddings": embeddings_list,
                "count": len(embeddings_list)
            }
            
            self.save_embeddings()
            self.save_metadata()
            
            # Save to MongoDB if available
            if self.mongo_client:
                self.faces_collection.update_one(
                    {'name': name},
                    {
                        '$set': {
                            'name': name,
                            'embeddings': [e.tolist() for e in embeddings_list],
                            'registered_date': self.registration_metadata[name]['date'],
                            'registered_time': self.registration_metadata[name]['time'],
                            'registered_datetime': self.registration_metadata[name]['datetime'],
                            'image_count': len(embeddings_list)
                        }
                    },
                    upsert=True
                )
            
            return {
                "success": True,
                "name": name,
                "images_processed": len(embeddings_list),
                "message": f"Registered {name}",
                "registered_date": self.registration_metadata[name]['date'],
                "registered_time": self.registration_metadata[name]['time']
            }
        
        return {"success": False, "message": "No valid faces detected"}

    # --- Save / Load embeddings ---
    def save_embeddings(self):
        with open(os.path.join(self.embeddings_dir, "facenet_embeddings.pkl"), 'wb') as f:
            pickle.dump(self.known_embeddings, f)

    def load_embeddings(self):
        path = os.path.join(self.embeddings_dir, "facenet_embeddings.pkl")
        if os.path.exists(path):
            with open(path, 'rb') as f:
                self.known_embeddings = pickle.load(f)

    # --- Metadata Management ---
    def save_metadata(self):
        with open(self.metadata_file, 'wb') as f:
            pickle.dump(self.registration_metadata, f)

    def load_metadata(self):
        if os.path.exists(self.metadata_file):
            with open(self.metadata_file, 'rb') as f:
                self.registration_metadata = pickle.load(f)

    # --- Last Seen ---
    def save_last_seen(self):
        with open(self.last_seen_file, 'wb') as f:
            pickle.dump(self.last_seen_time, f)

    def load_last_seen(self):
        if os.path.exists(self.last_seen_file):
            with open(self.last_seen_file, 'rb') as f:
                self.last_seen_time = pickle.load(f)

    # --- Cooldown check ---
    def can_detect_person(self, name):
        now = time.time()
        if name not in self.last_detection:
            return True
        return (now - self.last_detection[name]) >= self.detection_cooldown

    def record_detection(self, name):
        self.last_detection[name] = time.time()
        self.last_seen_time[name] = time.strftime("%Y/%m/%d %I:%M %p", time.localtime())
        self.save_last_seen()

    # --- Recognize Face ---
    def recognize_face(self, embedding):
        best_name = "Unknown"
        min_distance = float('inf')
        for name, data in self.known_embeddings.items():
            for e in data["embeddings"]:
                dist = 1 - np.dot(embedding, e / np.linalg.norm(e))
                if dist < min_distance:
                    min_distance = dist
                    best_name = name
        if min_distance <= self.threshold:
            return best_name, min_distance
        return "Unknown", min_distance

    # --- Position & Distance ---
    def estimate_distance(self, face_width_pixels):
        if face_width_pixels <= 0:
            return 0
        return round((self.KNOWN_FACE_WIDTH * self.FOCAL_LENGTH) / face_width_pixels, 2)

    def estimate_position(self, face_center_x, frame_width):
        left_bound = frame_width / 3
        right_bound = 2 * frame_width / 3
        if face_center_x < left_bound:
            return "left"
        elif face_center_x > right_bound:
            return "right"
        else:
            return "center"

    # --- Recognize From Image ---
    def recognize_from_image(self, image_path):
        image = cv2.imread(image_path)
        if image is None:
            return {'error': 'Failed to read image'}
        h, w, _ = image.shape

        # Detect face with bounding box
        boxes, _ = self.mtcnn.detect(image)
        if boxes is None or len(boxes) == 0:
            return {'error': 'No face detected'}

        x1, y1, x2, y2 = boxes[0]  # first detected face
        face_width = x2 - x1
        face_center_x = (x1 + x2) / 2

        # Always calculate position & distance
        position = self.estimate_position(face_center_x, w)
        distance_m = self.estimate_distance(face_width)

        # Extract embedding and recognize
        embedding = self.extract_face_embedding(image)
        name = "Unknown"
        sim_distance = 1.0
        if embedding is not None:
            name, sim_distance = self.recognize_face(embedding)

        # Last seen BEFORE updating
        last_seen_prev = self.last_seen_time.get(name) if name != "Unknown" else None

        # Record detection if known person
        if name != "Unknown" and self.can_detect_person(name):
            self.record_detection(name)

        confidence = max(0, 100 - int(sim_distance * 100)) if name != "Unknown" else 0

        # Announcement
        if name == "Unknown":
            announcement = f"Unknown person detected from your {position}, {distance_m} meters away."
        else:
            announcement = f"{name} detected from your {position}, {distance_m} meters away."
            if last_seen_prev:
                announcement += f" Last seen on {last_seen_prev}"

        return {
            'name': name,
            'confidence': confidence,
            'distance_m': distance_m,
            'position': position,
            'last_seen': last_seen_prev,
            'announcement': announcement,
            'face_box': [x1, y1, x2, y2]
        }

    # =========================================================================
    # NEW METHODS FOR PEOPLE MANAGEMENT
    # =========================================================================

    def get_all_registered_people(self):
        """Get all registered people with their details"""
        people_list = []
        
        for name, data in self.known_embeddings.items():
            # Get last seen information
            last_seen = self.last_seen_time.get(name, 'Never')
            
            person_info = {
                'id': name,  # Using name as ID for now
                'name': name,
                'images': data.get('count', 0),
                'date': self.registration_metadata.get(name, {}).get('date', 'N/A'),
                'time': self.registration_metadata.get(name, {}).get('time', 'N/A'),
                'datetime': self.registration_metadata.get(name, {}).get('datetime', 'N/A'),
                'last_seen': last_seen,
                'lastSeen': last_seen  # Add both formats for compatibility
            }
            people_list.append(person_info)
        
        # Sort by registration timestamp (newest first)
        people_list.sort(
            key=lambda x: self.registration_metadata.get(x['name'], {}).get('timestamp', 0),
            reverse=True
        )
        
        return people_list

    def get_person_by_id(self, person_id):
        """Get details of a specific person by ID (name)"""
        if person_id in self.known_embeddings:
            data = self.known_embeddings[person_id]
            return {
                'id': person_id,
                'name': person_id,
                'images': data.get('count', 0),
                'date': self.registration_metadata.get(person_id, {}).get('date', 'N/A'),
                'time': self.registration_metadata.get(person_id, {}).get('time', 'N/A'),
                'datetime': self.registration_metadata.get(person_id, {}).get('datetime', 'N/A'),
                'last_seen': self.last_seen_time.get(person_id, 'Never')
            }
        return None

    def delete_person(self, person_id):
        """Delete a registered person"""
        if person_id in self.known_embeddings:
            # Remove from embeddings
            del self.known_embeddings[person_id]
            
            # Remove from metadata
            if person_id in self.registration_metadata:
                del self.registration_metadata[person_id]
            
            # Remove from last seen
            if person_id in self.last_seen_time:
                del self.last_seen_time[person_id]
            
            # Remove from last detection
            if person_id in self.last_detection:
                del self.last_detection[person_id]
            
            # Delete image folder
            person_dir = os.path.join(self.known_faces_dir, person_id)
            if os.path.exists(person_dir):
                import shutil
                shutil.rmtree(person_dir)
            
            # Save updated data
            self.save_embeddings()
            self.save_metadata()
            self.save_last_seen()
            
            # Remove from MongoDB if available
            if self.mongo_client:
                self.faces_collection.delete_one({'name': person_id})
            
            return {
                'success': True,
                'message': f'Person {person_id} deleted successfully'
            }
        else:
            return {
                'success': False,
                'message': 'Person not found'
            }

    def update_person_name(self, old_name, new_name):
        """Update a person's name"""
        if old_name not in self.known_embeddings:
            return {
                'success': False,
                'message': 'Person not found'
            }
        
        if new_name in self.known_embeddings and new_name != old_name:
            return {
                'success': False,
                'message': 'Name already exists'
            }
        
        # Update embeddings
        self.known_embeddings[new_name] = self.known_embeddings.pop(old_name)
        
        # Update metadata
        if old_name in self.registration_metadata:
            self.registration_metadata[new_name] = self.registration_metadata.pop(old_name)
        
        # Update last seen
        if old_name in self.last_seen_time:
            self.last_seen_time[new_name] = self.last_seen_time.pop(old_name)
        
        # Update last detection
        if old_name in self.last_detection:
            self.last_detection[new_name] = self.last_detection.pop(old_name)
        
        # Rename folder
        old_dir = os.path.join(self.known_faces_dir, old_name)
        new_dir = os.path.join(self.known_faces_dir, new_name)
        if os.path.exists(old_dir):
            os.rename(old_dir, new_dir)
        
        # Save updated data
        self.save_embeddings()
        self.save_metadata()
        self.save_last_seen()
        
        # Update MongoDB if available
        if self.mongo_client:
            self.faces_collection.update_one(
                {'name': old_name},
                {'$set': {'name': new_name}}
            )
        
        return {
            'success': True,
            'message': f'Person renamed from {old_name} to {new_name}'
        }
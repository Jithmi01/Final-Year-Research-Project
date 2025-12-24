# FILE: services/face_recognition_service.py

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

        # Camera calibration for distance
        self.KNOWN_FACE_WIDTH = 0.16  # meters, average adult face width
        self.FOCAL_LENGTH = Config.FOCAL_LENGTH  # calibrated for your camera (see notes below)

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
            self.known_embeddings[name] = {"embeddings": embeddings_list, "count": len(embeddings_list)}
            self.save_embeddings()
            if self.mongo_client:
                self.faces_collection.update_one(
                    {'name': name},
                    {'$set': {'name': name, 'embeddings':[e.tolist() for e in embeddings_list]}},
                    upsert=True
                )
            return {"success": True, "name": name, "images_processed": len(embeddings_list), "message": f"Registered {name}"}
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
            'announcement': announcement
        }

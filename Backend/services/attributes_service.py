import cv2
import numpy as np
from tensorflow.keras.models import load_model
from config import Config

class AttributesService:
    def __init__(self):
        print("Loading attribute models...")
        self.models = {
            'accessories': load_model(Config.ACCESSORIES_MODEL_PATH, compile=False),
            'eyewear': load_model(Config.EYEWEAR_MODEL_PATH, compile=False),
            'facewear': load_model(Config.FACEWEAR_MODEL_PATH, compile=False),
            'headwear': load_model(Config.HEADWEAR_MODEL_PATH, compile=False),
            'nowear': load_model(Config.NOWEAR_MODEL_PATH, compile=False)
        }

        self.attributes = {
            'accessories': ['earrings', 'necklace', 'no_accessories', 'piercings'],
            'eyewear': [ 'eyecover','eyeglasses', 'no_eyewear', 'sunglasses'],
            'facewear': [ 'covered','fullmask', 'mouthmask', 'no_facewear'],
            'headwear': ['headtop', 'helmet', 'hoodie', 'no_headwear'],
            'nowear': ['facemarks', 'facepaint', 'facialhair', 'plain']
        }

        self.having_attributes = ['facemarks', 'facepaint', 'facialhair']
        self.face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
        self.input_size = (Config.ATTR_IMG_SIZE, Config.ATTR_IMG_SIZE)

    def enhance_face(self, face_rgb):
        try:
            lab = cv2.cvtColor(face_rgb, cv2.COLOR_RGB2LAB)
            l, a, b = cv2.split(lab)
            clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
            l = clahe.apply(l)
            lab = cv2.merge((l, a, b))
            face = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
            face = cv2.bilateralFilter(face, 5, 50, 50)
            return face
        except:
            return face_rgb

    def preprocess_face(self, face_img_rgb):
        face = cv2.resize(face_img_rgb, self.input_size, interpolation=cv2.INTER_LANCZOS4)
        arr = face.astype('float32') / 255.0
        return np.expand_dims(arr, axis=0)

    def predict_attribute(self, face_img_rgb, model_name):
        preprocessed = self.preprocess_face(face_img_rgb)
        probs = self.models[model_name].predict(preprocessed, verbose=0)[0]
        sorted_idx = np.argsort(probs)[::-1]
        top_idx = int(sorted_idx[0])
        top_conf = float(probs[top_idx])
        predicted_class = self.attributes[model_name][top_idx]
        second_conf = float(probs[sorted_idx[1]]) if len(sorted_idx) > 1 else 0.0
        conf_gap = top_conf - second_conf
        return predicted_class, top_conf, conf_gap, probs

    def detect_attributes(self, face_img_rgb):
        detected = {'wearing': [], 'having': []}
        confidences = {}
        for model_name in self.models.keys():
            attr, conf, gap, probs = self.predict_attribute(face_img_rgb, model_name)
            confidences[model_name] = {'attribute': attr, 'confidence': round(conf, 4), 'gap': round(gap,4)}
            threshold = Config.CONFIDENCE_THRESHOLDS[model_name]
            if conf >= threshold and gap >= Config.MIN_CONFIDENCE_GAP:
                if attr not in ['plain', 'no_accessories', 'no_eyewear', 'no_facewear', 'no_headwear']:
                    if attr in self.having_attributes:
                        detected['having'].append(attr)
                    else:
                        detected['wearing'].append(attr)
        return detected, confidences

    def format_announcement(self, detected):
        wearing = detected['wearing']
        having = detected['having']
        parts = []
        if wearing:
            parts.append(f"wearing {', '.join(wearing)}")
        if having:
            parts.append(f"having {', '.join(having)}")
        if not parts:
            return "No distinctive attributes detected"
        return "Person is " + " and ".join(parts)

    def extract_face_region(self, frame_rgb, x, y, w, h):
        pad = int(0.35*h)
        x1 = max(0, x-pad)
        y1 = max(0, y-pad)
        x2 = min(frame_rgb.shape[1], x+w+pad)
        y2 = min(frame_rgb.shape[0], y+h+pad)
        return frame_rgb[y1:y2, x1:x2]

    def detect_from_image(self, image_path):
        frame = cv2.imread(image_path)
        if frame is None:
            return {'error': 'Cannot read image'}
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = self.face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(100,100))
        if len(faces)==0:
            return {'error':'No face detected'}
        x,y,w,h = faces[0]
        face_rgb = self.extract_face_region(frame_rgb, x, y, w, h)
        face_rgb = self.enhance_face(face_rgb)
        detected, confidences = self.detect_attributes(face_rgb)
        announcement = self.format_announcement(detected)
        return {'attributes': detected, 'confidences': confidences, 'announcement': announcement, 'faces_detected': len(faces), 'face_location': {'x':int(x),'y':int(y),'w':int(w),'h':int(h)}}

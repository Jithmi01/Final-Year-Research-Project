import cv2
import numpy as np
import tensorflow as tf
from tensorflow.keras.models import load_model
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.applications import EfficientNetV2S
from tensorflow.keras.layers import GlobalAveragePooling2D, Dense, Dropout
from tensorflow.keras.models import Model
from config import Config
import logging

logger = logging.getLogger(__name__)

# Fix DepthwiseConv2D issues in older TF versions
from tensorflow.keras.layers import DepthwiseConv2D as KerasDepthwiseConv2D
class DepthwiseConv2D(KerasDepthwiseConv2D):
    def __init__(self, *args, **kwargs):
        kwargs.pop("groups", None)
        super().__init__(*args, **kwargs)

class AgeGenderService:
    def __init__(self):
        self.IMG_SIZE = 220
        self.AGE_LABELS = [
            "Baby(0-2)", "Toddler(3-6)", "Child(7-13)", "Teen(14-20)",
            "Young Adult(21-32)", "Adult(33-43)", "Middle Age(44-53)", "Senior(54+)"
        ]

        # Haar Cascade face detector
        self.face_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        )
        if self.face_cascade.empty():
            raise Exception("Failed to load Haar Cascade for face detection")

        # Load model
        self.model = self._load_model()
        logger.info("✓ Age & Gender model loaded successfully")

    def _load_model(self):
        try:
            logger.info("Loading model...")
            model = load_model(
                Config.AGE_GENDER_MODEL_PATH, 
                compile=False,
                custom_objects={"DepthwiseConv2D": DepthwiseConv2D}
            )

            model.compile(
                optimizer=Adam(learning_rate=0.0003),
                loss={
                    "gender": "binary_crossentropy",
                    "age": "sparse_categorical_crossentropy"
                },
                loss_weights={"gender": 0.4, "age": 0.6},
                metrics={"gender": "accuracy", "age": "accuracy"}
            )
            return model

        except Exception as e:
            logger.warning(f"Direct model loading failed: {e}")
            logger.info("Trying rebuild + load weights...")

            # Rebuild architecture
            base = EfficientNetV2S(include_top=False, weights=None,
                                    input_shape=(self.IMG_SIZE, self.IMG_SIZE, 3))
            x = GlobalAveragePooling2D()(base.output)
            x = Dense(256, activation="swish")(x)
            x = Dropout(0.25)(x)

            # Gender head
            g = Dense(64, activation="swish")(x)
            g = Dropout(0.15)(g)
            gender_out = Dense(1, activation="sigmoid", name="gender")(g)

            # Age head
            a = Dense(128, activation="swish")(x)
            a = Dropout(0.20)(a)
            age_out = Dense(8, activation="softmax", name="age")(a)

            model = Model(inputs=base.input, outputs=[gender_out, age_out])
            model.load_weights(Config.AGE_GENDER_MODEL_PATH)
            model.compile(
                optimizer=Adam(learning_rate=0.0003),
                loss={"gender": "binary_crossentropy", "age": "sparse_categorical_crossentropy"},
                loss_weights={"gender": 0.4, "age": 0.6},
                metrics={"gender": "accuracy", "age": "accuracy"}
            )
            logger.info("✓ Model rebuilt and weights loaded successfully")
            return model

    def preprocess_face(self, face_img):
        face_resized = cv2.resize(face_img, (self.IMG_SIZE, self.IMG_SIZE))
        face_rgb = cv2.cvtColor(face_resized, cv2.COLOR_BGR2RGB)
        face_normalized = face_rgb.astype(np.float32) / 255.0
        face_batch = np.expand_dims(face_normalized, axis=0)
        return face_batch

    def predict_age_gender(self, face_img):
        processed = self.preprocess_face(face_img)
        gender_pred, age_pred = self.model.predict(processed, verbose=0)

        gender_prob = float(gender_pred[0][0])
        gender = "Female" if gender_prob > 0.5 else "Male"
        gender_conf = gender_prob if gender_prob > 0.5 else (1 - gender_prob)

        age_idx = int(np.argmax(age_pred[0]))
        age_group = self.AGE_LABELS[age_idx]
        age_conf = float(age_pred[0][age_idx])

        return {
            "gender": gender,
            "gender_confidence": round(gender_conf * 100, 2),
            "age_group": age_group,
            "age_confidence": round(age_conf * 100, 2)
        }

    def detect_from_image(self, image_path, strategy="smart"):
        try:
            frame = cv2.imread(image_path)
            if frame is None:
                return {"error": "Could not read image"}

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            faces = self.face_cascade.detectMultiScale(
                gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60),
                flags=cv2.CASCADE_SCALE_IMAGE
            )

            if len(faces) == 0:
                return {"error": "No face detected"}

            x, y, w, h = faces[0]
            padding = int(0.2 * w)
            x1 = max(0, x - padding)
            y1 = max(0, y - padding)
            x2 = min(frame.shape[1], x + w + padding)
            y2 = min(frame.shape[0], y + h + padding)

            face_img = frame[y1:y2, x1:x2]
            if face_img.shape[0] < 20 or face_img.shape[1] < 20:
                return {"error": "Face too small"}

            result = self.predict_age_gender(face_img)
            result["faces_detected"] = len(faces)
            result["announcement"] = f"{result['gender']} person detected, about {result['age_group']}."
            return result

        except Exception as e:
            logger.error(f"Detection error: {e}")
            return {"error": str(e)}

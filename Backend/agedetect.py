#agedetect.py


import cv2
import numpy as np
import tensorflow as tf
from tensorflow.keras.models import load_model
import pyttsx3  # For text-to-speech
from collections import Counter  # For stabilizing predictions
import time  # For adding delay
import threading  # For non-blocking TTS


# CONFIGURATION

MODEL_PATH = r"C:\Users\HP\Jithmi\Jithmi\Jithmi\New folder\final_model_20251130-230919.h5"

IMG_SIZE = 224  

AGE_LABELS = [
    "Baby(0-2)", "Toddler(3-6)", "Child(7-13)", "Teen(14-20)",
    "Young Adult(21-32)", "Adult(33-43)", "Middle Age(44-53)", "Senior(54+)"
]

# Colors for display (BGR format)
COLOR_MALE = (255, 100, 100)      # Blue
COLOR_FEMALE = (180, 100, 255)    # Pink
COLOR_TEXT = (255, 255, 255)      # White
COLOR_BOX = (0, 255, 0)           # Green


# LOAD MODEL (with compatibility fix)

print("Loading model...")
try:
    model = load_model(MODEL_PATH, compile=False)
    
    from tensorflow.keras.optimizers import Adam
    model.compile(
        optimizer=Adam(learning_rate=0.0003),
        loss={
            "gender": "binary_crossentropy",
            "age": "sparse_categorical_crossentropy"
        },
        loss_weights={"gender": 0.4, "age": 0.6},
        metrics={"gender": "accuracy", "age": "accuracy"}
    )
    print(f"✓ Model loaded: {MODEL_PATH}")
except Exception as e:
    print(f"❌ Error loading model: {e}")
    print("\nTrying alternative loading method...")
    
    try:
        from tensorflow.keras.applications import EfficientNetV2S
        from tensorflow.keras.layers import GlobalAveragePooling2D, Dense, Dropout
        from tensorflow.keras.models import Model
        
        base = EfficientNetV2S(
            include_top=False,
            weights=None,
            input_shape=(IMG_SIZE, IMG_SIZE, 3)
        )
        
        x = GlobalAveragePooling2D()(base.output)
        x = Dense(256, activation="swish")(x)
        x = Dropout(0.25)(x)
        
        g = Dense(64, activation="swish")(x)
        g = Dropout(0.15)(g)
        gender_out = Dense(1, activation="sigmoid", name="gender")(g)
        
        a = Dense(128, activation="swish")(x)
        a = Dropout(0.20)(a)
        age_out = Dense(8, activation="softmax", name="age")(a)
        
        model = Model(inputs=base.input, outputs=[gender_out, age_out])
        model.load_weights(MODEL_PATH)
        
        print(f"✓ Model loaded with custom architecture")
    except Exception as e2:
        print(f"❌ Alternative method also failed: {e2}")
        print("\nPlease try one of these solutions:")
        print("1. Upgrade TensorFlow: pip install --upgrade tensorflow")
        print("2. Use the model that matches your TensorFlow version")
        print("3. Retrain the model with your current TensorFlow version")
        exit()


# LOAD FACE DETECTOR (Haar Cascade)

face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')

if face_cascade.empty():
    print("❌ Error: Could not load face detector")
    exit()

print("✓ Face detector loaded")


# PREDICTION FUNCTION

def preprocess_face(face_img):
    """Preprocess face image for model prediction"""
    face_resized = cv2.resize(face_img, (IMG_SIZE, IMG_SIZE))
    face_rgb = cv2.cvtColor(face_resized, cv2.COLOR_BGR2RGB)
    face_normalized = face_rgb.astype(np.float32) / 255.0
    face_batch = np.expand_dims(face_normalized, axis=0)
    return face_batch

def predict_age_gender(face_img):
    """Predict age group and gender from face image"""
    processed = preprocess_face(face_img)
    
    # Get predictions
    gender_pred, age_pred = model.predict(processed, verbose=0)
    
    # Process gender (0 = Male, 1 = Female)
    gender_prob = gender_pred[0][0]
    gender = "Female" if gender_prob > 0.5 else "Male"
    gender_confidence = gender_prob if gender_prob > 0.5 else (1 - gender_prob)
    
    # Process age
    age_idx = np.argmax(age_pred[0])
    age_group = AGE_LABELS[age_idx]
    age_confidence = age_pred[0][age_idx]
    
    return gender, gender_confidence, age_group, age_confidence

# Initialize text-to-speech engine
engine = pyttsx3.init()
engine.setProperty('rate', 150)
engine.setProperty('volume', 1.0)

def announce_detection_async(gender, age_group):
    """Announce the detected gender and age group in a separate thread"""
    def speak():
        message = f"{gender} person is detected, about {age_group}."
        engine.say(message)
        engine.runAndWait()
    
    # Run TTS in a separate thread to avoid blocking
    thread = threading.Thread(target=speak)
    thread.daemon = True
    thread.start()


# MAIN CAMERA LOOP

def main():
    print("\n" + "="*60)
    print("REAL-TIME AGE & GENDER DETECTION")
    print("="*60)
    print("Press 'q' to quit")
    print("Press 's' to save screenshot")
    print("="*60 + "\n")
    
    # Open webcam
    cap = cv2.VideoCapture(0)
    
    if not cap.isOpened():
        print("❌ Error: Could not open webcam")
        return
    
    # Set camera resolution
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    
    print("✓ Camera opened. Starting detection...")
    
    screenshot_count = 0
    last_announcement_time = 0
    last_detected_info = None  # Store last detection for display
    
    while True:
        ret, frame = cap.read()
        if not ret:
            print("❌ Failed to grab frame")
            break
        
        # Convert to grayscale for face detection
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        # Detect faces
        faces = face_cascade.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(60, 60),
            flags=cv2.CASCADE_SCALE_IMAGE
        )
        
        # Get current time
        current_time = time.time()
        
        # Check if 10 seconds have passed since last announcement
        should_announce = (current_time - last_announcement_time) >= 10
        
        # Track if we've announced in this cycle
        announced_this_cycle = False
        
        # Process each detected face
        for (x, y, w, h) in faces:
            # Extract face region with padding
            padding = int(0.2 * w)
            x1 = max(0, x - padding)
            y1 = max(0, y - padding)
            x2 = min(frame.shape[1], x + w + padding)
            y2 = min(frame.shape[0], y + h + padding)
            
            face_img = frame[y1:y2, x1:x2]
            
            # Skip if face is too small
            if face_img.shape[0] < 20 or face_img.shape[1] < 20:
                continue
            
            # Predict age and gender
            try:
                gender, gender_conf, age_group, age_conf = predict_age_gender(face_img)
                
                # Store detection info
                last_detected_info = (gender, gender_conf, age_group, age_conf)
                
                # Announce and print if 10 seconds have passed
                if should_announce and not announced_this_cycle:
                    message = f"{gender} person is detected, about {age_group}."
                    print(message)
                    announce_detection_async(gender, age_group)
                    last_announcement_time = current_time
                    announced_this_cycle = True  # Mark that we've announced this cycle
                
                # Choose color based on gender
                box_color = COLOR_FEMALE if gender == "Female" else COLOR_MALE
                
                # Draw bounding box
                cv2.rectangle(frame, (x, y), (x+w, y+h), box_color, 3)
                
                # Prepare text
                gender_text = f"{gender} ({gender_conf*100:.0f}%)"
                age_text = f"{age_group} ({age_conf*100:.0f}%)"
                
                # Draw background for text
                text_y = y - 10
                if text_y < 30:
                    text_y = y + h + 25
                
                # Gender text
                cv2.rectangle(frame, (x, text_y - 25), (x + w, text_y - 5), box_color, -1)
                cv2.putText(frame, gender_text, (x + 5, text_y - 10),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 2)
                
                # Age text
                cv2.rectangle(frame, (x, text_y), (x + w, text_y + 20), box_color, -1)
                cv2.putText(frame, age_text, (x + 5, text_y + 15),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 2)
                
            except Exception as e:
                print(f"⚠ Prediction error: {e}")
                continue
        
        # Only show info overlay if faces are detected
        if len(faces) > 0:
            info_text = f"Faces Detected: {len(faces)} | Press 'q' to quit, 's' to save"
        else:
            info_text = "No faces detected | Press 'q' to quit, 's' to save"
            last_detected_info = None  # Clear detection info when no faces
        
        cv2.rectangle(frame, (10, 10), (650, 40), (0, 0, 0), -1)
        cv2.putText(frame, info_text, (15, 30),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
        
        # Show frame (this ensures camera stays live)
        cv2.imshow('Age & Gender Detection', frame)
        
        # Handle keyboard input with shorter wait time for responsiveness
        key = cv2.waitKey(1) & 0xFF
        
        if key == ord('q'):
            print("\n✓ Exiting...")
            break
        elif key == ord('s'):
            screenshot_count += 1
            filename = f"screenshot_{screenshot_count}.jpg"
            cv2.imwrite(filename, frame)
            print(f"✓ Screenshot saved: {filename}")
    
    # Cleanup
    cap.release()
    cv2.destroyAllWindows()
    cv2.waitKey(1)  # Extra waitKey to ensure window closes
    print("✓ Camera closed")


if __name__ == "__main__":
    main()
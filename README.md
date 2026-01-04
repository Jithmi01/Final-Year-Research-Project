# 📱 Smart Assistive Mobile Application for Visually Impaired Users

![Status](https://img.shields.io/badge/STATUS-LIVE-success)
![Flutter](https://img.shields.io/badge/FLUTTER-3.x-blue)
![Dart](https://img.shields.io/badge/DART-3.x-0175C2)
![Python](https://img.shields.io/badge/PYTHON-3.11-blue)
![Flask](https://img.shields.io/badge/FLASK-3.0-lightgrey)
![TensorFlow](https://img.shields.io/badge/TENSORFLOW-2.20-orange)
![PyTorch](https://img.shields.io/badge/PYTORCH-2.1-red)
![OpenCV](https://img.shields.io/badge/OPENCV-4.8-green)
![YOLO](https://img.shields.io/badge/YOLO-Ultralytics-yellow)
![FaceNet](https://img.shields.io/badge/FACENET-Recognition-purple)
![OCR](https://img.shields.io/badge/OCR-Tesseract%20%7C%20EasyOCR-blueviolet)
![AI](https://img.shields.io/badge/AI-Computer%20Vision-purple)

---

**Final Year Research Project**  
**Project ID:** 25-26J-303  
**Target Users:** Visually Impaired Individuals  

An **AI-powered assistive mobile application** that enhances **visual awareness, safety, and independence** of visually impaired users through **real-time computer vision, voice interaction, and intelligent decision-making**.

---

##  Table of Contents

- [Overview](#overview)
- [Research Problem](#research-problem)
- [Proposed Solution](#proposed-solution)
- [Architecture Diagram](#architecture-diagram)
- [System Architecture](#system-architecture)
- [Key Features](#key-features)
- [Datasets](#datasets)
- [Project Structure](#-project-structure)
- [Project Setup](#project-setup)
- [Usage](#usage)
- [Ethical Considerations](#ethical-considerations)
- [Expected Impact](#expected-impact)
- [References](#references)
- [License](#license)

---

## Overview

Visually impaired individuals face daily challenges in understanding their surroundings, identifying people, reading currency, navigating environments, and selecting appropriate clothing.  
Existing solutions often focus on **single isolated features**, resulting in fragmented assistance.

This project proposes a **unified, AI-driven mobile application** that integrates:

- Person recognition  
- Face attribute analysis  
- Age & gender prediction  
- Distance estimation  
- Voice-guided navigation  
- Currency & document reading  
- Wardrobe recommendation  

All features are delivered via **hands-free voice interaction**, ensuring accessibility and ease of use.

---

## Research Problem

Current assistive technologies suffer from:

- Lack of contextual awareness  
- Inability to distinguish known vs unknown persons  
- Absence of multi-person understanding  
- Poor integration of vision, voice, and navigation  
- Limited real-time performance on mobile devices  

This research addresses these gaps by introducing a **real-time, multi-model, backend-powered AI system** optimized for visually impaired users.

---

## Proposed Solution

The system consists of **four integrated AI components**:

### 1️⃣ Voice-Guided Intelligent Vision Assistant
- Real-time face detection & recognition  
- Known vs unknown person identification  
- Age & gender prediction  
- Face attribute detection (eye glasses, masks, headwear, accessories, etc.)  
- Distance & position awareness
- Multiple person detection
- Voice feedback for blind user queries.
  

### 2️⃣ Smart Currency & Document Reader
- Currency recognition  
- OCR-based bill & document reading
- Automatic expense detection from scanned bills & receipts
- Categorization of expenses (Food, Transport, Utilities, etc.)
- smart wallet concept
- Speech-to-text & text-to-speech  
- Hands-free financial assistance
- Context-aware voice announcements 

### 3️⃣ Smart Context Aware Navigation Assistant
- Object Detection & Identification 
- Object finding using Voice command 
- Spatial Awareness
- Contextual Queries
- Obstacle Avoidance
- IoT Smart Stick

### 4️⃣ AI Wardrobe Recommendation System
- CNN-based clothing classification  
- Event & weather-based outfit suggestions  
- Fully voice-controlled interaction  

---
## Architechture Diagram

<img width="1374" height="746" alt="image" src="Architechtural daigram.png" />

---
## System Architecture

- **Frontend:** Flutter Mobile Application  
- **Backend:** Flask REST API  
- **AI Models:** CNN, FaceNet, YOLO, OCR  
- **Database:** Firebase  
- **Communication:** HTTP APIs  
- **Output:** Real-time audio feedback  

> Heavy AI inference is handled on the backend to maintain fast and responsive mobile performance.

---

##  Key Features

-  Voice-first interaction  
-  Real-time person recognition  
-  Age, gender & attribute prediction  
-  Distance & position estimation  
-  Currency & document reader  
-  Intelligent navigation assistance  
-  Wardrobe digitization & recommendations  
-  Secure & privacy-aware design  

---

##  Datasets

- UTKFace – Age & Gender  
- Face Attributes Grouped Dataset  
- Registered User Faces – Recognition
- Currency Image Dataset
- Document Image Dataset
- Custom Object Detection Dataset  
- Clothing Classification Dataset  

---
<img width="1536" height="1024" alt="ChatGPT Image Jan 3, 2026, 01_49_39 PM" src="https://github.com/user-attachments/assets/577d241a-3c0d-4e7c-84ce-790bce61dcd3" />

## 📂 Project Structure

```bash
project-root/
│
├── backend/
│   ├── app.py                # Main Flask app
│   ├── run.py                # App runner
│   ├── config.py             # Configuration settings
│   ├── models/               # Trained ML models
│   ├── routes/               # API route handlers
│   ├── services/             # Business logic
│   ├── requirements.txt      # Backend dependencies
│
├── frontend/
│   ├── lib/                  # Flutter source code
│   ├── android/              # Android build files
│   ├── ios/                  # iOS build files
│   ├── web/                  # Web support
│   ├── linux/                # Linux desktop
│   ├── macos/                # macOS desktop
│   ├── windows/              # Windows desktop
│   └── pubspec.yaml          # Flutter dependencies
│
├── README.md
└── LICENSE
```
---
## Project Setup

### Backend (Python)

```bash
cd backend
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```
### Frontend (Flutter)

```bash
cd frontend
flutter pub get
flutter run
```
---
## Usage

- Launch the mobile application
- Grant camera & microphone permissions
- Use voice commands to:
     - **Identify people**
     - **Read currency/documents**
     - **Navigate surroundings**
     - **Get outfit recommendations**
- Receive real-time audio feedback
---
## Ethical Considerations

- Consent-based face registration
- Secure storage of user data
- Privacy-aware announcements
- No unauthorized identity disclosure
- Research-use-only deployment
---
## Expected Impact

- Improved independence of visually impaired users
- Safer navigation & social interaction
- Reduced dependency on external assistance
- Practical application of AI for accessibility
- Alignment with inclusive technology goals
---
## References

- World Health Organization. (2024). Vision Impairment and Blindness
- Goodman-Deane et al. (2023). Assistive Technologies for Accessibility
- Zhang & Lee. (2022). Real-Time Face Attribute Recognition using CNNs
---
## License

- This project is developed for academic and research purposes only.
---

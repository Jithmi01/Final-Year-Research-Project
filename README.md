<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
</head>
<body>

<h1 align="center">📱 Smart Assistive Mobile Application for Visually Impaired Users</h1>
<p align="center"><strong>Final Year Research Project – 2025<br>Project ID: 25-26J-303</strong></p>

<hr>

<h2>1. Topic</h2>
<p><strong>AI-Powered Assistive Mobile App for Enhanced Visual Awareness and Safety</strong></p>

<hr>

<h2>2. Research Group</h2>
<p><strong>Group 25-26J-303</strong></p>

<hr>

<h2>3. Specialization</h2>
<p>
Artificial Intelligence (AI), Computer Vision, Mobile Application Development, Human–Computer Interaction (HCI)
</p>

<hr>

<h2>4. Previous Work Connection</h2>
<p><strong>Continuation of Project ID 25-26J-303 (Year: 2025)</strong></p>

<hr>

<h2>5. Brief Description of the Research Problem</h2>
<p>
Visual impairment limits an individual’s ability to perceive people, environments, and potential hazards in day-to-day life. 
Existing applications typically provide only basic features such as object detection or navigation support. However, these systems lack <strong>contextual awareness</strong>, <strong>multi-person understanding</strong>, and <strong>personalized recognition capability</strong>—all of which are essential for safe and independent mobility. 
Visually impaired individuals often struggle to identify whether nearby people are known or unknown, determine their distance or position, or receive descriptive information about their appearance. This gap restricts confidence, mobility, and interaction with surroundings.
</p>

<p>
Furthermore, current mobile assistive systems rarely integrate <strong>real-time face recognition</strong>, <strong>age and gender prediction</strong>, <strong>face attribute detection</strong> (e.g., eyewear, headwear), and <strong>context-aware announcement systems</strong> in one unified platform. 
This creates a fragmented experience and reduces reliability for visually impaired users who rely heavily on auditory feedback. 
Addressing these limitations can significantly improve independence, safety, and social engagement for users with vision disabilities.
</p>

<p>
This research aims to develop a <strong>real-time, AI-driven mobile application</strong> capable of identifying known persons, detecting unknown individuals with attributes, predicting age and gender, estimating distance and position, and announcing this information through audio feedback. The solution integrates machine learning models, optimized computer vision pipelines, and mobile-friendly deployment techniques to ensure fast, accurate, and accessible performance.
</p>

<h3>References</h3>
<ul>
  <li>World Health Organization. (2024). Vision Impairment and Blindness.</li>
  <li>Goodman-Deane, J. et al. (2023). Assistive Technologies for Accessibility: A Review of Advances in AI.</li>
  <li>Zhang, X., & Lee, S. (2022). Real-Time Face Attribute Recognition Using Lightweight CNN Models.</li>
</ul>

<hr>

<h2>6. Nature of the Proposed Solution</h2>
<p>
The proposed solution is a <strong>smart assistive mobile application</strong> combining computer vision, audio processing, and mobile computing. 
The system consists of four major components:
</p>

<ol>
  <li>
    <h3>Smart Vision Assistant</h3>
    <p>
      Powered by computer vision and machine learning to detect and identify people in real time, distinguishing between known and unknown individuals while estimating their position and distance. The system detects human attributes such as age, gender, eyewear, headwear, mouthwear, and accessories. Based on user voice instructions, it selectively announces the relevant person’s details through audio output, enabling hands-free and accessible environmental awareness for visually impaired users.
    </p>
  </li>
 
  <li>
    <h3>Voice-Guided Intelligent Vision Assistant</h3>
    <p>
      Powered by OCR and NLP to read printed or handwritten text, recognize currency, and categorize 
      transactions automatically. Includes speech-to-text and text-to-speech features for complete hands-free use.
    </p>
  </li>

  <li>
    <h3>Emotion-Adaptive AI Navigation Stick</h3>
    <p>
      Provides intelligent navigation through real-time scene understanding, obstacle detection, and 
      user behavior learning. Adapts guidance cues based on the user’s emotional state and environment, 
      offering personalized audio instructions for safe mobility.
    </p>
  </li>

  <li>
    <h3>AI-Driven Wardrobe Recommendation System</h3>
    <p>
      Digitizes the user’s wardrobe and classifies clothing with a CNN-based model. Generates outfit 
      recommendations based on body profile, event type, and weather. Fully voice-enabled for easy interaction.
    </p>
  </li>
</ol>

<p>
The mobile application communicates with a backend Flask API that performs the heavy ML model inference, ensuring fast and reliable predictions. The objective is to create an end-to-end assistive system that improves environmental understanding for visually impaired users.
</p>

<h3>Conceptual Diagram</h3>
<p align="center">
<img src="https://via.placeholder.com/700x400?text=Conceptual+Diagram+Placeholder" alt="Conceptual Diagram Placeholder">
</p>

<hr>

<h2>7. Specialized Domain Expertise, Knowledge & Data Requirements</h2>
<p>
Developing this assistive solution requires interdisciplinary expertise in machine learning, computer vision, mobile development, and accessibility engineering. 
The team needs strong understanding in:
</p>

<ul>
  <li><strong>Computer Vision:</strong> Face recognition, face embeddings, bounding box extraction, distance estimation, multi-person tracking.</li>
  <li><strong>Machine Learning:</strong> Age & gender prediction, face attribute classification using lightweight models.</li>
  <li><strong>Mobile App Development:</strong> Flutter camera integration, audio output, real-time API communication.</li>
  <li><strong>Backend Engineering:</strong> Flask endpoints, model optimization, GPU/CPU inference, concurrency handling.</li>
  <li><strong>Accessibility Design:</strong> Voice feedback, user-friendly interactions for visually impaired users.</li>
</ul>

<p>
The system requires datasets for:
</p>

<ul>
  <li>Object detection</li>
  <li>Face recognition (known users’ registered photos)</li>
  <li>Age and gender datasets (e.g., UTKFace)</li>
  <li>Face attribute datasets (e.g., CelebA)</li>
  <li>Currency detection</li>
  <li>Bill Scanner</li>
  <li>Fashion detection</li>
</ul>

<p>
Domain knowledge in human behavior, safety considerations, and user testing with visually impaired individuals is essential to ensure usability and accuracy. Ethical handling of face data and privacy must also be considered throughout the development lifecycle.
</p>

<hr>

<h2>📂 Project Repository Structure</h2>
<pre>
/project-root
│── backend/
│   ├── app.py
│   ├── models/
│   ├── utilities/
│   └── requirements.txt
│
│── frontend/
│   ├── lib/
│   ├── assets/
│   └── pubspec.yaml
│── README.html
│── LICENSE
</pre>

<hr>


</body>
</html>

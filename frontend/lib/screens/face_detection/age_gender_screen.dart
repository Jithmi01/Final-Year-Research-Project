import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '/services/api_service.dart';

class AgeGenderScreen extends StatefulWidget {
  const AgeGenderScreen({super.key});

  @override
  State<AgeGenderScreen> createState() => _AgeGenderScreenState();
}

class _AgeGenderScreenState extends State<AgeGenderScreen> {
  final FlutterTts flutterTts = FlutterTts();
  
  List<CameraDescription>? cameras;
  CameraController? _cameraController;
  bool _isFrontCamera = true;
  File? _capturedImage;
  Map<String, dynamic>? _detectionResult;
  bool _isLoading = false;
  String? _errorMessage;
  bool _serverConnected = false;
  bool _showCapturedImage = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkServerConnection();
    _initCamera();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    _speak("Age and Gender Detection. Camera is ready. Tap screen to capture photo.");
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
  }

  Future<void> _checkServerConnection() async {
    final connected = await ApiService.checkHealth();
    setState(() {
      _serverConnected = connected;
    });
    
    if (!connected) {
      _speak("Warning: Server not connected");
    }
  }

  Future<void> _initCamera() async {
    cameras = await availableCameras();
    _startCamera();
  }

  void _startCamera() {
    if (cameras == null || cameras!.isEmpty) return;
    
    final camera = _isFrontCamera
        ? cameras!.firstWhere((c) => c.lensDirection == CameraLensDirection.front)
        : cameras!.firstWhere((c) => c.lensDirection == CameraLensDirection.back);

    _cameraController?.dispose();
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _switchCamera() {
    setState(() => _isFrontCamera = !_isFrontCamera);
    _startCamera();
    _speak(_isFrontCamera ? "Switched to front camera" : "Switched to back camera");
  }

  Future<void> _captureAndDetect() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isLoading) {
      _speak("Camera not ready");
      return;
    }

    try {
      _speak("Capturing image");
      final image = await _cameraController!.takePicture();
      final file = File(image.path);

      setState(() {
        _capturedImage = file;
        _showCapturedImage = true;
        _isLoading = true;
        _errorMessage = null;
        _detectionResult = null;
      });

      _speak("Processing image");
      await _detectAgeGender(file);
    } catch (e) {
      _speak("Error capturing image");
      setState(() {
        _errorMessage = "Capture failed: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _detectAgeGender(File imageFile) async {
    try {
      final result = await ApiService.detectAgeGender(imageFile);
      
      if (result.containsKey('error')) {
        throw Exception(result['error']);
      }
      
      setState(() {
        _detectionResult = result;
        _isLoading = false;
      });

      if (result['announcement'] != null) {
        _speak(result['announcement']);
      }
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      
      if (e.toString().contains('No face detected')) {
        _speak("No face detected. Please try again with a clear face photo.");
      } else {
        _speak("Detection failed. Please try again.");
      }
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImage = null;
      _showCapturedImage = false;
      _detectionResult = null;
      _errorMessage = null;
    });
    _speak("Ready to capture new photo. Tap screen.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        title: Text('Age & Gender Detection'),
        actions: [
          IconButton(
            icon: Icon(
              _serverConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _serverConnected ? Colors.green : Colors.red,
            ),
            onPressed: _checkServerConnection,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera or Captured Image View
          Positioned.fill(
            child: GestureDetector(
              onTap: _showCapturedImage ? null : _captureAndDetect,
              child: _showCapturedImage && _capturedImage != null
                  ? _buildCapturedImageView()
                  : _buildCameraView(),
            ),
          ),

          // Camera Switch Button (only show when camera is active)
          if (!_showCapturedImage)
            Positioned(
              top: 20,
              right: 20,
              child: _buildCameraSwitchButton(),
            ),

          // Face Detection Indicator
          if (_detectionResult != null && _showCapturedImage)
            Positioned.fill(
              child: CustomPaint(
                painter: FaceIndicatorPainter(),
              ),
            ),

          // Loading Indicator
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: Colors.blue,
                        strokeWidth: 4,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Detecting age and gender...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Result Overlay
          if (_detectionResult != null && !_isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildResultOverlay(),
            ),

          // Error Message
          if (_errorMessage != null && !_isLoading)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: _buildErrorCard(),
            ),

          // Retake Button
          if (_showCapturedImage && !_isLoading)
            Positioned(
              top: 20,
              left: 20,
              child: _buildRetakeButton(),
            ),

          // Tap Instruction (only when camera is ready)
          if (!_showCapturedImage && !_isLoading)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Tap anywhere to capture',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: CameraPreview(_cameraController!),
    );
  }

  Widget _buildCapturedImageView() {
    return Container(
      color: Colors.black,
      child: Image.file(
        _capturedImage!,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildCameraSwitchButton() {
    return GestureDetector(
      onTap: _switchCamera,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.flip_camera_ios,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildRetakeButton() {
    return GestureDetector(
      onTap: _retakePhoto,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'Retake',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    final gender = _detectionResult!['gender'] ?? 'Unknown';
    final genderConf = _detectionResult!['gender_confidence'] ?? 0.0;
    final ageGroup = _detectionResult!['age_group'] ?? 'Unknown';
    final ageConf = _detectionResult!['age_confidence'] ?? 0.0;

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[900]!, Colors.blue[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Detection Complete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  icon: Icons.person,
                  label: 'Gender',
                  value: gender,
                  confidence: genderConf,
                  color: gender == 'Female' ? Colors.pink[300]! : Colors.blue[300]!,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  icon: Icons.cake,
                  label: 'Age Group',
                  value: ageGroup,
                  confidence: ageConf,
                  color: Colors.purple[300]!,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          GestureDetector(
            onTap: () => _speak(_detectionResult!['announcement'] ?? ''),
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.volume_up, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _detectionResult!['announcement'] ?? '',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required double confidence,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            '${confidence.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    flutterTts.stop();
    super.dispose();
  }
}

class FaceIndicatorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width * 0.3;

    canvas.drawCircle(Offset(centerX, centerY), radius, paint);

    // Draw corner brackets
    final bracketLength = radius * 0.3;
    final bracketPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(
      Offset(centerX - radius, centerY - radius),
      Offset(centerX - radius + bracketLength, centerY - radius),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(centerX - radius, centerY - radius),
      Offset(centerX - radius, centerY - radius + bracketLength),
      bracketPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(centerX + radius, centerY - radius),
      Offset(centerX + radius - bracketLength, centerY - radius),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(centerX + radius, centerY - radius),
      Offset(centerX + radius, centerY - radius + bracketLength),
      bracketPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(centerX - radius, centerY + radius),
      Offset(centerX - radius + bracketLength, centerY + radius),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(centerX - radius, centerY + radius),
      Offset(centerX - radius, centerY + radius - bracketLength),
      bracketPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(centerX + radius, centerY + radius),
      Offset(centerX + radius - bracketLength, centerY + radius),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(centerX + radius, centerY + radius),
      Offset(centerX + radius, centerY + radius - bracketLength),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
// FILE: lib/screens/face_detection/live_face_detection_screen.dart
// Unified Live Face Detection for Blind Users

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '/services/api_service.dart';

class LiveFaceDetectionScreen extends StatefulWidget {
  const LiveFaceDetectionScreen({super.key});

  @override
  State<LiveFaceDetectionScreen> createState() => _LiveFaceDetectionScreenState();
}

class _LiveFaceDetectionScreenState extends State<LiveFaceDetectionScreen> {
  final FlutterTts flutterTts = FlutterTts();
  
  List<CameraDescription>? cameras;
  CameraController? _cameraController;
  bool _isFrontCamera = false; // Changed to false to start with back camera
  bool _cameraInitialized = false; // Track initialization status
  
  // Detection states
  bool _isAnalyzing = false;
  bool _faceDetectedInFrame = false;
  Timer? _detectionTimer;
  int _consecutiveFaceDetections = 0; // Track consecutive detections
  
  // Results
  Map<String, dynamic>? _analysisResult;
  bool _showResults = false;
  
  @override
  void initState() {
    super.initState();
    _initTts();
    _initCamera();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
    
    // Welcome announcement
    await Future.delayed(Duration(milliseconds: 500));
    _speak("Live face detection activated. Camera is opening. Point camera at a person's face.");
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
  }

  Future<void> _initCamera() async {
    cameras = await availableCameras();
    _startCamera();
    
    // Start periodic face detection for voice feedback
    _detectionTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (!_isAnalyzing && _cameraController != null && _cameraController!.value.isInitialized) {
        _quickFaceCheck();
      }
    });
  }

  void _startCamera() {
    if (cameras == null || cameras!.isEmpty) return;
    
    final camera = _isFrontCamera
        ? cameras!.firstWhere((c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => cameras!.first)
        : cameras!.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => cameras!.first);

    _cameraController?.dispose();
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _cameraInitialized = true);
      _speak("Camera ready. ${_isFrontCamera ? 'Front' : 'Back'} camera active. Tap screen when face is detected.");
    }).catchError((error) {
      print('Camera error: $error');
      _speak("Camera initialization failed. Please restart the app.");
    });
  }

  void _switchCamera() {
    if (!_cameraInitialized) return; // Prevent switching before initialization
    setState(() => _isFrontCamera = !_isFrontCamera);
    _startCamera();
  }

  /// Quick face detection for voice feedback (runs periodically)
  Future<void> _quickFaceCheck() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final image = await _cameraController!.takePicture();
      final file = File(image.path);

      final result = await ApiService.quickFaceDetect(file);
      
      // Use direct face_detected value from API
      bool faceDetected = result['face_detected'] ?? false;
      
      if (faceDetected) {
        _consecutiveFaceDetections++;
      } else {
        _consecutiveFaceDetections = 0;
      }
      
      // Require 2 consecutive detections to announce (prevents false positives)
      if (_consecutiveFaceDetections >= 2 && !_faceDetectedInFrame) {
        _speak("Face detected! Tap screen to analyze.");
        setState(() => _faceDetectedInFrame = true);
      } else if (_consecutiveFaceDetections == 0 && _faceDetectedInFrame) {
        setState(() => _faceDetectedInFrame = false);
      }
      
      await file.delete();
    } catch (e) {
      print('Quick detection error: $e');
    }
  }

  /// Full analysis when user taps screen
  Future<void> _analyzeCurrentFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isAnalyzing) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _showResults = false;
      _analysisResult = null;
    });

    try {
      _speak("Analyzing face. Please wait.");
      
      final image = await _cameraController!.takePicture();
      final file = File(image.path);

      print('📸 Image captured, sending for analysis...');

      final result = await ApiService.analyzeFace(file);
      
      await file.delete();

      print('📊 Analysis result: ${result['person_type']}');

      // Enhance announcement with last seen info for known persons
      if (result['person_type'] == 'known' && result['data'] != null) {
        final lastSeen = result['data']['last_seen'];
        if (lastSeen != null && result['announcement'] != null) {
          result['announcement'] = '${result['announcement']} ';
        }
      }

      setState(() {
        _analysisResult = result;
        _showResults = true;
        _isAnalyzing = false;
      });

      // Speak the announcement
      if (result['announcement'] != null) {
        await Future.delayed(Duration(milliseconds: 300));
        _speak(result['announcement']);
      }

    } catch (e) {
      print('❌ Analysis error: $e');
      setState(() => _isAnalyzing = false);
      _speak("Analysis failed. Please try again.");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _clearResults() {
    setState(() {
      _showResults = false;
      _analysisResult = null;
    });
    _speak("Ready for new detection. Tap screen when face is detected.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Row(
          children: [
            Icon(Icons.face_retouching_natural, color: Colors.white),
            SizedBox(width: 8),
            Text('Live Face Detection'),
          ],
        ),
        actions: [
          // Face detected indicator
          if (_faceDetectedInFrame && !_isAnalyzing)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.face, color: Colors.green, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'FACE',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: !_isAnalyzing && !_showResults ? _analyzeCurrentFrame : null,
        child: Stack(
          children: [
            // Camera Preview
            Positioned.fill(
              child: _buildCameraView(),
            ),

            // Camera Switch Button - Only show after initialization
            if (!_showResults && _cameraInitialized)
              Positioned(
                top: 20,
                right: 20,
                child: GestureDetector(
                  onTap: _switchCamera,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),

            // Face detected indicator overlay
            if (_faceDetectedInFrame && !_isAnalyzing && !_showResults)
              Positioned.fill(
                child: CustomPaint(
                  painter: FaceDetectionOverlayPainter(),
                ),
              ),

            // Voice instruction instead of button (no visual button needed for blind users)
            if (!_isAnalyzing && !_showResults && _faceDetectedInFrame)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green[700]!, Colors.green[500]!],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app,
                          color: Colors.white,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'FACE DETECTED - TAP TO ANALYZE',
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

            // Analyzing overlay
            if (_isAnalyzing)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            color: Colors.blue,
                            strokeWidth: 6,
                          ),
                        ),
                        SizedBox(height: 24),
                        Text(
                          'Analyzing Face...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Please wait',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Results overlay
            if (_showResults && _analysisResult != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildResultsOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Initializing camera...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: _cameraController!.value.aspectRatio,
      child: CameraPreview(_cameraController!),
    );
  }

  Widget _buildResultsOverlay() {
    final faceDetected = _analysisResult!['face_detected'] ?? false;
    
    if (!faceDetected) {
      return _buildErrorResult();
    }

    final personType = _analysisResult!['person_type'] ?? 'unknown';
    
    if (personType == 'known') {
      return _buildKnownPersonResult();
    } else {
      return _buildUnknownPersonResult();
    }
  }

  Widget _buildKnownPersonResult() {
    final data = _analysisResult!['data'];
    final name = data['name'] ?? 'Unknown';
    final confidence = data['confidence'] ?? 0;
    final distance = data['distance_m'] ?? 'unknown';
    final position = data['position'] ?? 'center';
    final lastSeen = data['last_seen'];

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[900]!, Colors.green[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person, color: Colors.white, size: 40),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Known Person',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          SizedBox(height: 20),
          Divider(color: Colors.white30, thickness: 1),
          SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.straighten,
                  label: 'Distance',
                  value: distance != 'unknown' ? '${distance}m' : 'Unknown',
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.place,
                  label: 'Position',
                  value: position,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          
          if (lastSeen != null) ...[
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Last seen: $lastSeen',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
          
          SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _speak(_analysisResult!['announcement']),
                  icon: Icon(Icons.volume_up),
                  label: Text('Repeat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _clearResults,
                  icon: Icon(Icons.refresh),
                  label: Text('New Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green[900],
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnknownPersonResult() {
    final data = _analysisResult!['data'];
    final distance = data['distance_m'] ?? 'unknown';
    final position = data['position'] ?? 'center';
    
    final ageGender = data['age_gender'];
    final attributes = data['attributes'];

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[900]!, Colors.orange[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_outline, color: Colors.white, size: 40),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unknown Person',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (ageGender != null && !ageGender.containsKey('error'))
                      Text(
                        '${ageGender['gender']} • ${ageGender['age_group']}',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                  ],
                ),
              ),
            ],
          ),
          
          SizedBox(height: 20),
          Divider(color: Colors.white30, thickness: 1),
          SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.straighten,
                  label: 'Distance',
                  value: distance != 'unknown' ? '${distance}m' : 'Unknown',
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.place,
                  label: 'Position',
                  value: position,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          
          if (attributes != null && !attributes.containsKey('error')) ...[
            SizedBox(height: 16),
            Text(
              'DETECTED ATTRIBUTES',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 8),
            _buildAttributesDisplay(attributes['attributes']),
          ],
          
          SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _speak(_analysisResult!['announcement']),
                  icon: Icon(Icons.volume_up),
                  label: Text('Repeat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _clearResults,
                  icon: Icon(Icons.refresh),
                  label: Text('New Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.orange[900],
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorResult() {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red[900]!, Colors.red[700]!],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 64),
          SizedBox(height: 16),
          Text(
            'No Face Detected',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _analysisResult!['announcement'] ?? 'Please try again',
            style: TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _clearResults,
            icon: Icon(Icons.refresh),
            label: Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red[900],
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
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
          Icon(icon, color: color, size: 24),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 12),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttributesDisplay(Map<String, dynamic>? attrs) {
    if (attrs == null) return SizedBox.shrink();
    
    final wearing = (attrs['wearing'] as List?)?.cast<String>() ?? [];
    final having = (attrs['having'] as List?)?.cast<String>() ?? [];
    
    if (wearing.isEmpty && having.isEmpty) {
      return Text(
        'No distinctive attributes',
        style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
      );
    }
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...wearing.map((attr) => Chip(
          label: Text(attr),
          backgroundColor: Colors.white.withOpacity(0.2),
          labelStyle: TextStyle(color: Colors.white),
        )),
        ...having.map((attr) => Chip(
          label: Text(attr),
          backgroundColor: Colors.white.withOpacity(0.2),
          labelStyle: TextStyle(color: Colors.white),
        )),
      ],
    );
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    flutterTts.stop();
    super.dispose();
  }
}

/// Custom painter for face detection overlay
class FaceDetectionOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    // Draw corner brackets
    final bracketLength = 80.0;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final boxSize = 200.0;

    final left = centerX - boxSize / 2;
    final right = centerX + boxSize / 2;
    final top = centerY - boxSize / 2;
    final bottom = centerY + boxSize / 2;

    // Top-left
    canvas.drawLine(Offset(left, top), Offset(left + bracketLength, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left, top + bracketLength), paint);

    // Top-right
    canvas.drawLine(Offset(right, top), Offset(right - bracketLength, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + bracketLength), paint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom), Offset(left + bracketLength, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left, bottom - bracketLength), paint);

    // Bottom-right
    canvas.drawLine(Offset(right, bottom), Offset(right - bracketLength, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - bracketLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import '/services/api_service.dart';

class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  final FlutterTts flutterTts = FlutterTts();

  bool _isLoading = false;

  List<CameraDescription>? cameras;
  CameraController? _cameraController;
  bool _isFrontCamera = true;

  Map<String, dynamic>? _recognitionResult;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initCamera();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    _speak("Face recognition screen. Tap to recognize faces.");
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
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
    );

    _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _switchCamera() {
    setState(() => _isFrontCamera = !_isFrontCamera);
    _startCamera();
    _speak(_isFrontCamera ? "Front camera" : "Back camera");
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isLoading) {
      return;
    }

    final image = await _cameraController!.takePicture();
    final file = File(image.path);

    setState(() {
      _isLoading = true;
      _recognitionResult = null;
    });

    _speak("Recognizing face");

    try {
      final result = await ApiService.recognizePerson(file);
      setState(() {
        _recognitionResult = result;
        _isLoading = false;
      });
      _speak(result['announcement'] ?? "Recognition completed");
    } catch (e) {
      _speak("Recognition failed");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        title: Text("Face Recognition"),
      ),
      body: _buildRecognitionView(),
    );
  }

  Widget _buildRecognitionView() {
    return Column(
      children: [
        // Camera View
        Expanded(
          child: Stack(
            children: [
              GestureDetector(
                onTap: _captureImage,
                child: _cameraController != null &&
                        _cameraController!.value.isInitialized
                    ? Container(
                        color: Colors.black,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CameraPreview(_cameraController!),
                            ),
                            if (_recognitionResult != null &&
                                _recognitionResult!['face_box'] != null)
                              CustomPaint(
                                painter: FaceBoxPainter(
                                  _recognitionResult!['face_box'],
                                  _cameraController!.value.previewSize!,
                                ),
                              ),
                          ],
                        ),
                      )
                    : Container(
                        color: Colors.black,
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
              ),

              // Camera Switch Button
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
                    ),
                    child: Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),

              // Capture Instruction
              if (!_isLoading)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Tap to recognize face',
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

              // Loading Overlay
              if (_isLoading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 4,
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Recognizing...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Recognition Result
        if (_recognitionResult != null && !_isLoading) _buildRecognitionResult(),
      ],
    );
  }

  Widget _buildRecognitionResult() {
    final name = _recognitionResult!['name'] ?? 'Unknown';
    final confidence = _recognitionResult!['confidence'] ?? 0;
    final distance = _recognitionResult!['distance_m'];
    final position = _recognitionResult!['position'];
    final lastSeen = _recognitionResult!['last_seen'];

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: name == 'Unknown'
              ? [Colors.red[900]!, Colors.red[700]!]
              : [Colors.green[900]!, Colors.green[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                name == 'Unknown' ? Icons.person_off : Icons.person,
                color: Colors.white,
                size: 32,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (name != 'Unknown')
                      Text(
                        'Confidence: $confidence%',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.straighten,
                  label: 'Distance',
                  value: '${distance}m',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildInfoChip(
                  icon: Icons.place,
                  label: 'Position',
                  value: position,
                ),
              ),
            ],
          ),
          if (lastSeen != null) ...[
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
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
          GestureDetector(
            onTap: () => _speak(_recognitionResult!['announcement'] ?? ''),
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
                      _recognitionResult!['announcement'] ?? '',
                      style: TextStyle(color: Colors.white, fontSize: 14),
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

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
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

class FaceBoxPainter extends CustomPainter {
  final List<dynamic> box;
  final Size previewSize;

  FaceBoxPainter(this.box, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final scaleX = size.width / previewSize.height;
    final scaleY = size.height / previewSize.width;

    final rect = Rect.fromLTWH(
      box[0] * scaleX,
      box[1] * scaleY,
      (box[2] - box[0]) * scaleX,
      (box[3] - box[1]) * scaleY,
    );

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_) => true;
}
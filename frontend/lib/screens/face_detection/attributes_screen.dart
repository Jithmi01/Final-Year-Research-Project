import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '/services/api_service.dart';

class AttributesScreen extends StatefulWidget {
  const AttributesScreen({super.key});

  @override
  State<AttributesScreen> createState() => _AttributesScreenState();
}

class _AttributesScreenState extends State<AttributesScreen> {
  final FlutterTts flutterTts = FlutterTts();
  
  List<CameraDescription>? cameras;
  CameraController? _cameraController;
  bool _isFrontCamera = true;
  File? _capturedImage;
  Map<String, dynamic>? _detectionResult;
  bool _isLoading = false;
  bool _showCapturedImage = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initCamera();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    _speak("Facial attributes detection. Camera is ready. Tap screen to capture.");
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

  Future<void> _captureAndDetect() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isLoading) {
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
        _detectionResult = null;
      });

      _speak("Detecting attributes");
      await _detectAttributes(file);
    } catch (e) {
      _speak("Error capturing image");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _detectAttributes(File imageFile) async {
    try {
      final result = await ApiService.detectAttributes(imageFile);
      
      setState(() {
        _detectionResult = result;
        _isLoading = false;
      });

      if (result['announcement'] != null) {
        _speak(result['announcement']);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _speak("Detection failed");
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImage = null;
      _showCapturedImage = false;
      _detectionResult = null;
    });
    _speak("Ready to capture. Tap screen.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        title: Text('Facial Attributes'),
      ),
      body: Stack(
        children: [
          // Camera or Captured Image
          Positioned.fill(
            child: GestureDetector(
              onTap: _showCapturedImage ? null : _captureAndDetect,
              child: _showCapturedImage && _capturedImage != null
                  ? _buildCapturedImageView()
                  : _buildCameraView(),
            ),
          ),

          // Camera Switch Button
          if (!_showCapturedImage)
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
                        color: Colors.purple,
                        strokeWidth: 4,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Detecting attributes...',
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

          // Retake Button
          if (_showCapturedImage && !_isLoading)
            Positioned(
              top: 20,
              left: 20,
              child: GestureDetector(
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
              ),
            ),

          // Tap Instruction
          if (!_showCapturedImage && !_isLoading)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.9),
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

  Widget _buildResultOverlay() {
    final attributes = _detectionResult!['attributes'] as Map<String, dynamic>?;
    final wearing = attributes?['wearing'] as List<dynamic>? ?? [];
    final having = attributes?['having'] as List<dynamic>? ?? [];
    final announcement = _detectionResult!['announcement'] ?? '';

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[900]!, Colors.purple[700]!],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.face_retouching_natural, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Detected Attributes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          if (wearing.isNotEmpty) ...[
            Text(
              'WEARING',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: wearing.map((attr) {
                return _buildAttributeChip(
                  attr.toString(),
                  _getAttributeIcon(attr.toString()),
                  _getAttributeColor(attr.toString()),
                );
              }).toList(),
            ),
            SizedBox(height: 16),
          ],

          if (having.isNotEmpty) ...[
            Text(
              'HAVING',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: having.map((attr) {
                return _buildAttributeChip(
                  attr.toString(),
                  _getAttributeIcon(attr.toString()),
                  _getAttributeColor(attr.toString()),
                );
              }).toList(),
            ),
            SizedBox(height: 16),
          ],

          if (wearing.isEmpty && having.isEmpty) ...[
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white70),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No distinctive attributes detected',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],

          Divider(color: Colors.white24, thickness: 1),
          SizedBox(height: 12),

          GestureDetector(
            onTap: () => _speak(announcement),
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.volume_up, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      announcement,
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

  Widget _buildAttributeChip(String attribute, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          SizedBox(width: 6),
          Text(
            attribute,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getAttributeIcon(String attribute) {
    switch (attribute.toLowerCase()) {
      case 'eyeglasses':
      case 'sunglasses':
      case 'eyecover':
        return Icons.visibility;
      case 'helmet':
      case 'hoodie':
      case 'headtop':
        return Icons.face;
      case 'mouthmask':
      case 'fullmask':
      case 'covered':
        return Icons.masks;
      case 'earrings':
      case 'necklace':
      case 'piercings':
        return Icons.diamond;
      case 'facialhair':
        return Icons.face_retouching_natural;
      case 'facemarks':
      case 'facepaint':
        return Icons.palette;
      default:
        return Icons.star;
    }
  }

  Color _getAttributeColor(String attribute) {
    switch (attribute.toLowerCase()) {
      case 'eyeglasses':
      case 'sunglasses':
      case 'eyecover':
        return Colors.blue[300]!;
      case 'helmet':
      case 'hoodie':
      case 'headtop':
        return Colors.orange[300]!;
      case 'mouthmask':
      case 'fullmask':
      case 'covered':
        return Colors.red[300]!;
      case 'earrings':
      case 'necklace':
      case 'piercings':
        return Colors.pink[300]!;
      case 'facialhair':
        return Colors.brown[300]!;
      case 'facemarks':
      case 'facepaint':
        return Colors.green[300]!;
      default:
        return Colors.purple[300]!;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    flutterTts.stop();
    super.dispose();
  }
}
// lib/screens/age_gender_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';

class AgeGenderScreen extends StatefulWidget {
  const AgeGenderScreen({super.key});

  @override
  State<AgeGenderScreen> createState() => _AgeGenderScreenState();
}


class _AgeGenderScreenState extends State<AgeGenderScreen> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts flutterTts = FlutterTts();
  
  File? _selectedImage;
  Map<String, dynamic>? _detectionResult;
  bool _isLoading = false;
  String? _errorMessage;
  bool _serverConnected = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkServerConnection();
  }

  Future<void> _initTts() async {
    try {
      await flutterTts.setLanguage("en-US");
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);
      _speak("Age and Gender Detection. Tap camera to capture, or gallery to select image.");
    } catch (e) {
      print('TTS initialization error: $e');
    }
  }

  Future<void> _checkServerConnection() async {
    final connected = await ApiService.checkHealth();
    setState(() {
      _serverConnected = connected;
    });
    
    if (!connected) {
      _showErrorDialog(
        'Server Connection Failed',
        'Cannot connect to server. Please check:\n'
        '1. Server is running (python app.py)\n'
        '2. Both devices on same WiFi\n'
        '3. IP address is correct in api_service.dart'
      );
    }
  }

  Future<void> _speak(String text) async {
    try {
      await flutterTts.speak(text);
    } catch (e) {
      print('TTS error: $e');
    }
  }

//

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _detectionResult = null;
          _errorMessage = null;
        });
        
        _speak("Image selected. Processing...");
        await _detectAgeGender();
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error selecting image: $e";
      });
      _speak("Error selecting image");
      _showSnackBar('Error: $e', isError: true);
    }
  }

  Future<void> _detectAgeGender() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.detectAgeGender(_selectedImage!);
      
      // Check if result contains error
      if (result.containsKey('error')) {
        throw Exception(result['error']);
      }
      
      setState(() {
        _detectionResult = result;
        _isLoading = false;
        _errorMessage = null;
      });

      // Announce result
      if (result['announcement'] != null) {
        _speak(result['announcement']);
      } else {
        _speak("${result['gender']} person detected, about ${result['age_group']}");
      }
      
      _showSnackBar('Detection successful!', isError: false);
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _detectionResult = null;
        _errorMessage = e.toString();
      });
      
      String errorMsg = e.toString();
      
      // Provide helpful error messages
      if (errorMsg.contains('No face detected')) {
        _speak("No face detected. Please try a clearer image with a visible face.");
        _showErrorDialog(
          'No Face Detected',
          'Please ensure:\n'
          '• Face is clearly visible\n'
          '• Good lighting\n'
          '• Front-facing photo\n'
          '• Face is at least 60x60 pixels'
        );
      } else if (errorMsg.contains('Connection timeout') || errorMsg.contains('Cannot connect')) {
        _speak("Connection error. Please check server connection.");
        _showErrorDialog(
          'Connection Error',
          'Cannot connect to server.\n\n'
          'Please check:\n'
          '• Server is running (python app.py)\n'
          '• Both devices on same WiFi\n'
          '• IP address in api_service.dart is correct'
        );
      } else {
        _speak("Detection failed: $errorMsg");
        _showSnackBar('Error: $errorMsg', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        duration: Duration(seconds: isError ? 4 : 2),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
          if (title.contains('Connection'))
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _checkServerConnection();
              },
              child: Text('Retry'),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _serverConnected ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _serverConnected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _serverConnected ? Icons.check_circle : Icons.error,
            color: _serverConnected ? Colors.green : Colors.red,
            size: 20,
          ),
          SizedBox(width: 8),
          Text(
            _serverConnected ? 'Server Connected' : 'Server Disconnected',
            style: TextStyle(
              color: _serverConnected ? Colors.green[900] : Colors.red[900],
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh, size: 20),
            onPressed: _checkServerConnection,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    if (_detectionResult == null) return const SizedBox.shrink();

    final gender = _detectionResult!['gender'] ?? 'Unknown';
    final genderConf = _detectionResult!['gender_confidence'] ?? 0.0;
    final ageGroup = _detectionResult!['age_group'] ?? 'Unknown';
    final ageConf = _detectionResult!['age_confidence'] ?? 0.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text(
                  'Detection Result',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Divider(height: 24),
            _buildResultRow(
              icon: Icons.person,
              label: 'Gender',
              value: gender,
              confidence: genderConf,
              color: gender == 'Female' ? Colors.pink : Colors.blue,
            ),
            SizedBox(height: 12),
            _buildResultRow(
              icon: Icons.cake,
              label: 'Age Group',
              value: ageGroup,
              confidence: ageConf,
              color: Colors.purple,
            ),
            Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.volume_up, color: Colors.blue[700]),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _detectionResult!['announcement'] ?? 
                      '$gender person detected, about $ageGroup.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.replay, color: Colors.blue[700]),
                    onPressed: () {
                      _speak(_detectionResult!['announcement'] ?? '');
                    },
                    tooltip: 'Replay announcement',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow({
    required IconData icon,
    required String label,
    required String value,
    required double confidence,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${confidence.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    if (_errorMessage == null) return SizedBox.shrink();

    return Card(
      color: Colors.red[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[900]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Age & Gender Detection'),
        actions: [
          Padding(
            padding: EdgeInsets.all(8),
            child: _buildConnectionStatus(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedImage != null)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    _selectedImage!,
                    height: 300,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            
            if (_selectedImage == null)
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[400]!, width: 2),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, 
                           size: 80, 
                           color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(
                        'No image selected',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () {
                      _speak("Opening camera");
                      _pickImage(ImageSource.camera);
                    },
                    icon: const Icon(Icons.camera_alt, size: 28),
                    label: const Text('Camera', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () {
                      _speak("Opening gallery");
                      _pickImage(ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo_library, size: 28),
                    label: const Text('Gallery', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            if (_isLoading)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 3),
                      SizedBox(height: 16),
                      Text(
                        'Detecting age and gender...',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            
            if (!_isLoading) _buildErrorCard(),
            if (!_isLoading) _buildResultCard(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }
}
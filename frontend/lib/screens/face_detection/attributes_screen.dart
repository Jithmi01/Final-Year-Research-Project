import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api_service.dart';

class AttributesScreen extends StatefulWidget {
  const AttributesScreen({super.key});

  @override
  State<AttributesScreen> createState() => _AttributesScreenState();
}

class _AttributesScreenState extends State<AttributesScreen> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts flutterTts = FlutterTts();
  
  File? _selectedImage;
  Map<String, dynamic>? _detectionResult;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _speak("Attributes Detection. Take a photo to detect facial attributes.");
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await flutterTts.speak(text);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _detectionResult = null;
        });
        
        _speak("Image selected. Detecting attributes...");
        await _detectAttributes();
      }
    } catch (e) {
      _speak("Error selecting image");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _detectAttributes() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await ApiService.detectAttributes(_selectedImage!);
      
      setState(() {
        _detectionResult = result;
        _isLoading = false;
      });

      // Announce result
      if (result['announcement'] != null) {
        _speak(result['announcement']);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      _speak("Detection failed: ${e.toString()}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Widget _buildAttributeChip(String attribute, String category) {
    IconData icon;
    Color color;
    
    switch (category) {
      case 'eyewear':
        icon = Icons.visibility;
        color = Colors.blue;
        break;
      case 'headwear':
        icon = Icons.face;
        color = Colors.orange;
        break;
      case 'facewear':
        icon = Icons.masks;
        color = Colors.red;
        break;
      case 'accessories':
        icon = Icons.star;
        color = Colors.purple;
        break;
      default:
        icon = Icons.palette;
        color = Colors.green;
    }
    
    return Chip(
      avatar: Icon(icon, size: 18, color: Colors.white),
      label: Text(
        attribute,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: color,
    );
  }

  Widget _buildResultCard() {
    if (_detectionResult == null) return const SizedBox.shrink();

    final attributes = _detectionResult!['attributes'] as Map<String, dynamic>?;
    final wearing = attributes?['wearing'] as List<dynamic>? ?? [];
    final having = attributes?['having'] as List<dynamic>? ?? [];
    final confidences = _detectionResult!['confidences'] as Map<String, dynamic>?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detected Attributes:',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            if (wearing.isNotEmpty) ...[
              const Text(
                'Wearing:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: wearing.map((attr) {
                  return _buildAttributeChip(attr.toString(), 'wearing');
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            
            if (having.isNotEmpty) ...[
              const Text(
                'Having:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: having.map((attr) {
                  return _buildAttributeChip(attr.toString(), 'having');
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            
            if (wearing.isEmpty && having.isEmpty) ...[
              const Text(
                'No distinctive attributes detected',
                style: TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            const Divider(),
            const SizedBox(height: 8),
            
            // Announcement
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.volume_up, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _detectionResult!['announcement'] ?? '',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            
            if (confidences != null) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Detection Confidences'),
                children: [
                  ...confidences.entries.map((entry) {
                    final model = entry.key;
                    final data = entry.value as Map<String, dynamic>;
                    final attr = data['attribute'];
                    final conf = (data['confidence'] as num).toStringAsFixed(2);
                    
                    return ListTile(
                      dense: true,
                      title: Text(model),
                      subtitle: Text('$attr ($conf)'),
                    );
                  }).toList(),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attributes Detection'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedImage != null)
              Card(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    _selectedImage!,
                    height: 300,
                    fit: BoxFit.cover,
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
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Detecting attributes...'),
                  ],
                ),
              ),
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
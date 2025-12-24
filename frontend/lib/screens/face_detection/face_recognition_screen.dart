import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api_service.dart';

class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController _nameController = TextEditingController();

  bool _isRegistering = false;
  List<File> _registrationImages = [];
  File? _recognitionImage;
  Map<String, dynamic>? _recognitionResult;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _speak(
        "Face Recognition. You can register a new person or recognize someone.");
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

  // ---------------- Registration ----------------
  Future<void> _addRegistrationImage() async {
    if (_registrationImages.length >= 5) {
      _speak("Maximum 5 images allowed");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 images allowed')),
      );
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _registrationImages.add(File(image.path));
        });
        _speak(
            "Image ${_registrationImages.length} added. ${5 - _registrationImages.length} remaining.");
      }
    } catch (e) {
      _speak("Error capturing image");
    }
  }

  Future<void> _registerPerson() async {
    if (_nameController.text.isEmpty) {
      _speak("Please enter a name");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    if (_registrationImages.isEmpty) {
      _speak("Please add at least one image");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one image')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await ApiService.registerPerson(
        _nameController.text,
        _registrationImages,
      );

      _speak(result['message'] ?? 'Registration successful');

      setState(() {
        _isLoading = false;
        _registrationImages.clear();
        _nameController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Success')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _speak("Registration failed: ${e.toString()}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ---------------- Recognition ----------------
  Future<void> _recognizePerson(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _recognitionImage = File(image.path);
          _recognitionResult = null;
          _isLoading = true;
        });

        _speak("Processing image...");

        final result = await ApiService.recognizePerson(_recognitionImage!);

        setState(() {
          _recognitionResult = result;
          _isLoading = false;
        });

        if (result['announcement'] != null) {
          _speak(result['announcement']);
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _speak("Recognition failed: ${e.toString()}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ---------------- UI Widgets ----------------
  Widget _buildRegistrationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Register New Person',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Person Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            Text('Images: ${_registrationImages.length}/5',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            if (_registrationImages.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _registrationImages.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: FileImage(_registrationImages[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _registrationImages.removeAt(index);
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _addRegistrationImage,
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Add Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _registerPerson,
                    icon: const Icon(Icons.save),
                    label: const Text('Register'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecognitionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Recognize Person',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_recognitionImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _recognitionImage!,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _recognizePerson(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _recognizePerson(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_recognitionResult != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _recognitionResult!['name'] == 'Unknown'
                      ? Colors.red[50]
                      : Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _recognitionResult!['name'] == 'Unknown'
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Name: ${_recognitionResult!['name']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_recognitionResult!['distance_m'] != null)
                      Text(
                        'Distance: ${_recognitionResult!['distance_m']} m',
                        style: const TextStyle(fontSize: 16),
                      ),
                    if (_recognitionResult!['position'] != null)
                      Text(
                        'Position: ${_recognitionResult!['position']}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    if (_recognitionResult!['last_seen'] != null)
                      Text(
                        'Last seen: ${_recognitionResult!['last_seen']}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.volume_up, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _recognitionResult!['announcement'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- Main Build ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Recognition'),
        actions: [
          Switch(
            value: _isRegistering,
            onChanged: (value) {
              setState(() {
                _isRegistering = value;
              });
              _speak(_isRegistering ? "Registration mode" : "Recognition mode");
            },
            activeColor: Colors.white,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_isRegistering)
              _buildRegistrationSection()
            else
              _buildRecognitionSection(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    flutterTts.stop();
    super.dispose();
  }
}
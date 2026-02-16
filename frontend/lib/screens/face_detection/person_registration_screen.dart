// lib/screens/face_detection/person_registration_screen.dart - WITH VOICE OPTION
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import '/services/api_service.dart';
import '/services/audio_service.dart';

class PersonRegistrationScreen extends StatefulWidget {
  const PersonRegistrationScreen({super.key});

  @override
  State<PersonRegistrationScreen> createState() => _PersonRegistrationScreenState();
}

class _PersonRegistrationScreenState extends State<PersonRegistrationScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AudioService _audioService = AudioService();

  bool _isLoading = false;
  List<File> _registrationImages = [];
  List<String> _voiceSamples = [];
  
  // Tab selection
  int _currentTab = 0; // 0 = Face, 1 = Voice, 2 = Both
  
  // Voice recording
  bool _isRecording = false;
  int _recordingCountdown = 0;
  final int _recordDuration = 5;
  final int _requiredVoiceSamples = 3;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await flutterTts.setSpeechRate(0.5);
    _speak("Person registration screen. You can register with photos, voice, or both.");
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
  }

  Future<void> _pickImageForRegistration() async {
    if (_registrationImages.length >= 5) {
      _speak("Maximum five images reached");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum 5 images allowed')),
      );
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() => _registrationImages.add(File(image.path)));
        _speak("Image ${_registrationImages.length} added");
      }
    } catch (e) {
      _speak("Error selecting image");
    }
  }
  
  Future<void> _recordVoiceSample() async {
    if (_voiceSamples.length >= _requiredVoiceSamples) {
      _speak("Maximum voice samples reached");
      return;
    }
    
    if (!await _audioService.hasPermission()) {
      final granted = await _audioService.requestPermission();
      if (!granted) {
        _speak("Microphone permission required");
        return;
      }
    }
    
    setState(() {
      _isRecording = true;
      _recordingCountdown = _recordDuration;
    });
    
    await _speak("Recording. Please speak now.");
    await Future.delayed(Duration(milliseconds: 500));
    
    final started = await _audioService.startRecording();
    if (!started) {
      setState(() => _isRecording = false);
      _speak("Recording failed");
      return;
    }
    
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_recordingCountdown > 0) {
        setState(() => _recordingCountdown--);
      } else {
        timer.cancel();
      }
    });
    
    await Future.delayed(Duration(seconds: _recordDuration));
    
    if (!mounted) return;
    
    final path = await _audioService.stopRecording();
    
    setState(() => _isRecording = false);
    
    if (path != null) {
      setState(() => _voiceSamples.add(path));
      _speak("Voice sample ${_voiceSamples.length} recorded");
    } else {
      _speak("Recording failed");
    }
  }

  Future<void> _registerPerson() async {
    if (_nameController.text.isEmpty) {
      _speak("Please enter a name");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a name')),
      );
      return;
    }
    
    if (_registrationImages.isEmpty && _voiceSamples.isEmpty) {
      _speak("Add at least one photo or voice sample");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add at least one photo or voice sample')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Register face if images provided
      if (_registrationImages.isNotEmpty) {
        final res = await ApiService.registerPerson(
          _nameController.text,
          _registrationImages,
        );
        _speak("Face registered successfully");
      }
      
      // Register voice if samples provided
      if (_voiceSamples.isNotEmpty) {
        final voiceRes = await ApiService.registerVoiceUser(
          name: _nameController.text,
          audioFilePaths: _voiceSamples,
        );
        _speak("Voice registered successfully");
      }

      _speak("${_nameController.text} registered successfully");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration successful'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _registrationImages.clear();
        _voiceSamples.clear();
        _nameController.clear();
        _isLoading = false;
      });

      Navigator.pop(context, true);
    } catch (e) {
      _speak("Registration failed");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    } finally {
      // Cleanup voice files
      for (final path in _voiceSamples) {
        await _audioService.deleteAudioFile(path);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        title: Text("Register Person", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange[800]!, Colors.orange[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registration Options',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Register with photos, voice, or both',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24),

            // Name Input
            Text(
              'Person Name',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: "Enter person's name",
                hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(Icons.person, color: Colors.orange),
                filled: true,
                fillColor: Color(0xFF3C3C3C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            SizedBox(height: 24),

            // Tab Selector
            Container(
              decoration: BoxDecoration(
                color: Color(0xFF3C3C3C),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton('Photos', 0, Icons.photo_camera),
                  ),
                  Expanded(
                    child: _buildTabButton('Voice', 1, Icons.mic),
                  ),
                  Expanded(
                    child: _buildTabButton('Both', 2, Icons.merge_type),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24),

            // Content based on tab
            if (_currentTab == 0 || _currentTab == 2) ...[
              _buildPhotoSection(),
              if (_currentTab == 2) SizedBox(height: 24),
            ],
            
            if (_currentTab == 1 || _currentTab == 2)
              _buildVoiceSection(),

            SizedBox(height: 24),

            // Register Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading || _isRecording ? null : _registerPerson,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_add, size: 24),
                          SizedBox(width: 8),
                          Text(
                            "Register Person",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index, IconData icon) {
    final isSelected = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Photos (${_registrationImages.length}/5)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _registrationImages.length < 5 ? _pickImageForRegistration : null,
              icon: Icon(Icons.add_photo_alternate),
              label: Text('Add Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        if (_registrationImages.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _registrationImages.length,
            itemBuilder: (context, index) {
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _registrationImages[index],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _registrationImages.removeAt(index));
                        _speak("Image removed");
                      },
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              );
            },
          )
        else
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[700]!, width: 2),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, size: 60, color: Colors.grey[600]),
                  SizedBox(height: 12),
                  Text('No photos added yet', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVoiceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Voice Samples (${_voiceSamples.length}/$_requiredVoiceSamples)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: (_voiceSamples.length < _requiredVoiceSamples && !_isRecording) 
                  ? _recordVoiceSample 
                  : null,
              icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
              label: Text(_isRecording ? 'Recording...' : 'Record'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.blue[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        
        if (_isRecording) ...[
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red, width: 2),
            ),
            child: Column(
              children: [
                Icon(Icons.fiber_manual_record, size: 48, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  '$_recordingCountdown',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                Text(
                  'seconds remaining',
                  style: TextStyle(color: Colors.red[300]),
                ),
              ],
            ),
          ),
        ],
        
        SizedBox(height: 16),
        ...List.generate(_requiredVoiceSamples, (index) {
          final isRecorded = index < _voiceSamples.length;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  isRecorded ? Icons.check_circle : Icons.circle_outlined,
                  color: isRecorded ? Colors.green : Colors.grey,
                  size: 24,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Voice Sample ${index + 1}',
                    style: TextStyle(
                      fontSize: 16,
                      color: isRecorded ? Colors.white : Colors.grey,
                      fontWeight: isRecorded ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (isRecorded)
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 20),
                    color: Colors.red,
                    onPressed: () async {
                      await _audioService.deleteAudioFile(_voiceSamples[index]);
                      setState(() => _voiceSamples.removeAt(index));
                      _speak("Sample deleted");
                    },
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  void dispose() {
    flutterTts.stop();
    _nameController.dispose();
    _audioService.dispose();
    
    // Cleanup voice files
    for (final path in _voiceSamples) {
      _audioService.deleteAudioFile(path);
    }
    
    super.dispose();
  }
}
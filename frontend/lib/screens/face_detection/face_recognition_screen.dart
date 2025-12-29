import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import '/services/api_service.dart';

class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  final FlutterTts flutterTts = FlutterTts();
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isRegistering = false;
  bool _isLoading = false;
  List<File> _registrationImages = [];

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
    _speak("Face recognition screen. Switch mode using the toggle button.");
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

    if (_isRegistering) {
      _speak("Please use gallery to add photos for registration");
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

  Future<void> _registerPerson() async {
    if (_nameController.text.isEmpty) {
      _speak("Please enter a name");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a name')),
      );
      return;
    }
    if (_registrationImages.isEmpty) {
      _speak("Add at least one image");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add at least one image')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await ApiService.registerPerson(
        _nameController.text,
        _registrationImages,
      );

      _speak("${_nameController.text} registered successfully");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Registration successful'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _registrationImages.clear();
        _nameController.clear();
        _isLoading = false;
      });
    } catch (e) {
      _speak("Registration failed");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  void _showManagePeopleDialog() {
    _speak("Opening people dashboard");
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PeopleDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        title: Text("Face Recognition"),
        actions: [
          IconButton(
            icon: Icon(Icons.dashboard, color: Colors.white),
            onPressed: _showManagePeopleDialog,
            tooltip: 'People Dashboard',
          ),
          Container(
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: _isRegistering ? Colors.orange[700] : Colors.green[700],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 12),
                Text(
                  _isRegistering ? 'Register' : 'Recognize',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: _isRegistering,
                  onChanged: (v) {
                    setState(() {
                      _isRegistering = v;
                      _recognitionResult = null;
                      _registrationImages.clear();
                      _nameController.clear();
                    });
                    _speak(v ? "Registration mode. Use gallery to add photos." : "Recognition mode. Tap screen to recognize.");
                  },
                  activeColor: Colors.white,
                  activeTrackColor: Colors.orange[300],
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.green[300],
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isRegistering ? _buildRegistrationView() : _buildRecognitionView(),
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

  Widget _buildRegistrationView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instructions Card
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
                        'Registration Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Use gallery to add 1-5 photos of the person',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
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

          // Add Photos Section
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

          // Images Grid
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
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
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
                    Icon(
                      Icons.photo_library_outlined,
                      size: 60,
                      color: Colors.grey[600],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No photos added yet',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          SizedBox(height: 24),

          // Register Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _registerPerson,
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
    _nameController.dispose();
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

// People Dashboard Screen
class PeopleDashboardScreen extends StatefulWidget {
  @override
  State<PeopleDashboardScreen> createState() => _PeopleDashboardScreenState();
}

class _PeopleDashboardScreenState extends State<PeopleDashboardScreen> {
  List<Map<String, dynamic>> registeredPeople = [];
  bool isLoading = true;
  int totalPeople = 0;
  int totalImages = 0;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    setState(() => isLoading = true);
    
    // TODO: Replace with actual API call
    await Future.delayed(Duration(seconds: 1));
    
    // Mock data
    final mockData = [
      {
        'name': 'John Doe',
        'images': 5,
        'date': '2024-12-15',
        'time': '10:30 AM',
        'lastSeen': '2024-12-28 02:15 PM'
      },
      {
        'name': 'Jane Smith',
        'images': 3,
        'date': '2024-12-20',
        'time': '03:45 PM',
        'lastSeen': '2024-12-27 11:20 AM'
      },
      {
        'name': 'Bob Johnson',
        'images': 4,
        'date': '2024-12-22',
        'time': '09:15 AM',
        'lastSeen': 'Never'
      },
    ];
    
    setState(() {
      registeredPeople = mockData;
      totalPeople = mockData.length;
      totalImages = mockData.fold(0, (sum, item) => sum + (item['images'] as int));
      isLoading = false;
    });
  }

  void _deletePerson(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2C2C2C),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Person', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete ${registeredPeople[index]['name']}? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => registeredPeople.removeAt(index));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Person deleted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              _updateStats();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _editPerson(int index) {
    final nameController = TextEditingController(text: registeredPeople[index]['name']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2C2C2C),
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.blue),
            SizedBox(width: 8),
            Text('Edit Person', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: TextField(
          controller: nameController,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                registeredPeople[index]['name'] = nameController.text;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Person updated successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _updateStats() {
    setState(() {
      totalPeople = registeredPeople.length;
      totalImages = registeredPeople.fold(0, (sum, item) => sum + (item['images'] as int));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        title: Text('People Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadPeople,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats Cards
                Container(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.people,
                          label: 'Total People',
                          value: totalPeople.toString(),
                          color: Colors.blue,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.photo_library,
                          label: 'Total Photos',
                          value: totalImages.toString(),
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

                // People List
                Expanded(
                  child: registeredPeople.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 80, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No registered people',
                                style: TextStyle(color: Colors.grey, fontSize: 18),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Register people using the registration mode',
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: registeredPeople.length,
                          itemBuilder: (context, index) {
                            final person = registeredPeople[index];
                            return Card(
                              color: Color(0xFF2C2C2C),
                              margin: EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Colors.orange[700],
                                          radius: 28,
                                          child: Text(
                                            person['name'][0].toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                person['name'],
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(Icons.photo, color: Colors.grey[600], size: 16),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    '${person['images']} photos',
                                                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: Icon(Icons.more_vert, color: Colors.white),
                                          color: Color(0xFF3C3C3C),
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _editPerson(index);
                                            } else if (value == 'delete') {
                                              _deletePerson(index);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, color: Colors.blue, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Edit', style: TextStyle(color: Colors.white)),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete, color: Colors.red, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Delete', style: TextStyle(color: Colors.white)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    Divider(color: Colors.grey[700], height: 1),
                                    SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildInfoItem(
                                            icon: Icons.calendar_today,
                                            label: 'Registered',
                                            value: '${person['date']}\n${person['time']}',
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 40,
                                          color: Colors.grey[700],
                                        ),
                                        Expanded(
                                          child: _buildInfoItem(
                                            icon: Icons.access_time,
                                            label: 'Last Seen',
                                            value: person['lastSeen'],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color.withOpacity(0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 32),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[500], size: 18),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
          ),
        ),
        SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
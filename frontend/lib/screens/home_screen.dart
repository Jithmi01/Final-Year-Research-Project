import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'face_recognition_screen.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterTts flutterTts = FlutterTts();
  bool isServerConnected = false;
  bool isCheckingConnection = true;

  @override
  void initState() {
    super.initState();
    _initTts();
    _checkServerConnection();
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

  Future<void> _checkServerConnection() async {
    setState(() {
      isCheckingConnection = true;
    });

    bool connected = await ApiService.checkHealth();

    setState(() {
      isServerConnected = connected;
      isCheckingConnection = false;
    });

    if (!connected) {
      _speak("Warning: Backend server is not connected. Please start the Flask server.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backend server not connected. Please start Flask server.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } else {
      _speak("Welcome to Blind Assistant. Server connected successfully.");
    }
  }

  Widget _buildFeatureCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        _speak(title);
        onTap();
      },
      child: Card(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.7), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 60, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blind Assistant'),
        actions: [
          if (isCheckingConnection)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(
                isServerConnected ? Icons.cloud_done : Icons.cloud_off,
                color: isServerConnected ? Colors.green : Colors.red,
              ),
              onPressed: _checkServerConnection,
              tooltip: isServerConnected ? 'Server Connected' : 'Server Disconnected',
            ),
        ],
      ),
      body: SafeArea(
        child: isCheckingConnection
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (!isServerConnected)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Backend server not connected. Tap to retry.',
                                style: TextStyle(color: Colors.red[900]),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _checkServerConnection,
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        children: [
                          _buildFeatureCard(
                            title: 'Age & Gender',
                            description: 'Detect age and gender',
                            icon: Icons.face,
                            color: Colors.blue,
                            onTap: () {
                              if (isServerConnected) {
                               ;
                              } else {
                                _speak("Please connect to server first");
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please connect to server first'),
                                  ),
                                );
                              }
                            },
                          ),
                          _buildFeatureCard(
                            title: 'Face Recognition',
                            description: 'Recognize known faces',
                            icon: Icons.person_search,
                            color: Colors.green,
                            onTap: () {
                              if (isServerConnected) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const FaceRecognitionScreen(),
                                  ),
                                );
                              } else {
                                _speak("Please connect to server first");
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please connect to server first'),
                                  ),
                                );
                              }
                            },
                          ),
                          _buildFeatureCard(
                            title: 'Attributes',
                            description: 'Detect facial attributes',
                            icon: Icons.visibility,
                            color: Colors.orange,
                            onTap: () {
                              if (isServerConnected) {
                               ;
                              } else {
                                _speak("Please connect to server first");
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please connect to server first'),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
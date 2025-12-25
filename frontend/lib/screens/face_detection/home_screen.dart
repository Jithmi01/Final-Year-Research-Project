import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'age_gender_screen.dart';
import 'face_recognition_screen.dart';
import 'attributes_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/voice_navigation_widget.dart';


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

  Widget _buildHeaderCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.face,
              size: 48,
              color: Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Face Recognition Features',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Voice-guided face analysis',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String emoji, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            emoji,
            style: TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: () {
        _speak(title);
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[600],
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.face, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Text(
              'Face Recognition',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          if (isCheckingConnection)
            Padding(
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
            Padding(
          padding: EdgeInsets.only(right: 8),
          child: VoiceNavigationWidget(currentPage: 'face_home'),
        ),
        ],
      ),
      body: SafeArea(
        child: isCheckingConnection
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isServerConnected)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red[900]?.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Backend server not connected. Tap to retry.',
                                style: TextStyle(color: Colors.red[300]),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.red),
                              onPressed: _checkServerConnection,
                            ),
                          ],
                        ),
                      ),
                    
                    _buildHeaderCard(),
                    
                    _buildSectionHeader('👤', 'Face Detection'),
                    
                    _buildFeatureCard(
                      title: 'Age & Gender Detector',
                      description: 'Detect age and gender from faces',
                      icon: Icons.face,
                      iconColor: Colors.white,
                      backgroundColor: Color(0xFF8B4513),
                      onTap: () {
                        if (isServerConnected) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AgeGenderScreen(),
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
                      badge: 'NEW',
                    ),
                    
                    _buildSectionHeader('🎭', 'Recognition'),
                    
                    _buildFeatureCard(
                      title: 'Face Recognition',
                      description: 'Recognize and identify known faces',
                      icon: Icons.person_search,
                      iconColor: Colors.white,
                      backgroundColor: Color(0xFF2E7D32),
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
                    
                    _buildSectionHeader('✨', 'Attributes'),
                    
                    _buildFeatureCard(
                      title: 'Facial Attributes',
                      description: 'Detect facial features and attributes',
                      icon: Icons.visibility,
                      iconColor: Colors.white,
                      backgroundColor: Color(0xFF1976D2),
                      onTap: () {
                        if (isServerConnected) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AttributesScreen(),
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
                    
                    const SizedBox(height: 24),
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


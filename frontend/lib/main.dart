// lib/main.dart - UNIFIED APP WITH VOICE NAVIGATION (FIXED)
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// Face Detection Imports
import 'screens/face_detection/home_screen.dart';
import 'screens/face_detection/age_gender_screen.dart';
import 'screens/face_detection/face_recognition_screen.dart';
import 'screens/face_detection/attributes_screen.dart';

// Currency & Bills Imports  
import 'screens/currency_bills/currency_bills_home.dart';
import 'pages/currency/ar_currency_detector_page.dart';
import 'pages/bills/bill_scanner_page.dart';
import 'pages/smart_wallet/wallet_scanner_page.dart';
import 'pages/smart_wallet/wallet_qa_page.dart';

// Voice Navigation Service
import 'services/voice_navigation_service.dart';

// API Configuration for Currency/Bills
const String YOUR_SERVER_IP = "192.168.8.143";
const String API_URL = "http://$YOUR_SERVER_IP:5000";

// Global camera list
late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const UnifiedAssistantApp());
}

class UnifiedAssistantApp extends StatelessWidget {
  const UnifiedAssistantApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[850],
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[850],
          elevation: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: MasterHomePage(),
    );
  }
}

class MasterHomePage extends StatefulWidget {
  const MasterHomePage({Key? key}) : super(key: key);

  @override
  State<MasterHomePage> createState() => _MasterHomePageState();
}

class _MasterHomePageState extends State<MasterHomePage> {
  final VoiceNavigationService _voiceService = VoiceNavigationService();
  bool _isVoiceEnabled = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeVoiceService();
  }

  Future<void> _initializeVoiceService() async {
    try {
      bool initialized = await _voiceService.initialize();
      if (mounted) {
        setState(() {
          _isVoiceEnabled = initialized;
        });
      }
      
      if (initialized) {
        await _voiceService.speak("Welcome to Smart Assistant. Press the microphone button to use voice navigation");
      } else {
        print('⚠️ Voice service not initialized');
      }
    } catch (e) {
      print('❌ Error initializing voice service: $e');
    }
  }

  void _handleVoiceCommand() async {
    // Prevent multiple simultaneous calls
    if (_isProcessing || _voiceService.isListening) {
      print('⚠️ Already processing or listening, ignoring tap');
      return;
    }

    if (!_isVoiceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voice navigation not available. Check microphone permission.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () async {
              await _voiceService.requestMicrophonePermission();
              _initializeVoiceService();
            },
          ),
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _voiceService.startListening(
        onResult: (command) async {
          print('📢 Processing command: $command');
          
          String? route = _voiceService.parseNavigationCommand(command);
          
          if (route != null) {
            String routeName = _voiceService.getRouteName(route);
            await _voiceService.speak("Navigating to $routeName");
            
            // Small delay for speech to start
            await Future.delayed(Duration(milliseconds: 800));
            
            // Navigate based on route
            if (mounted) {
              _navigateToRoute(route);
            }
          } else {
            await _voiceService.speak("Command not recognized. Please try again");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Command not recognized: $command'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
          
          // Reset processing state after everything is done
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        },
        onError: (error) async {
          print('❌ Voice error: $error');
          await _voiceService.speak("Voice error occurred. Please try again");
          
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $error'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
      );
      
      // Set a timeout to reset processing state if nothing happens
      Future.delayed(Duration(seconds: 10), () {
        if (mounted && _isProcessing) {
          print('⏱️ Timeout: resetting processing state');
          setState(() {
            _isProcessing = false;
          });
        }
      });
      
    } catch (e) {
      print('❌ Exception in voice command: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _navigateToRoute(String route) {
    Widget? page;
    
    switch (route) {
      case 'currency_home':
        page = CurrencyBillsHome();
        break;
      case 'ar_currency':
        if (cameras.isNotEmpty) {
          page = ARCurrencyDetectorPage(camera: cameras.first);
        }
        break;
      case 'bill_scanner':
        if (cameras.isNotEmpty) {
          page = BillScannerPage(camera: cameras.first);
        }
        break;
      case 'wallet_scanner':
        if (cameras.isNotEmpty) {
          page = WalletScannerPage(camera: cameras.first);
        }
        break;
      case 'wallet_qa':
        page = WalletQAPage();
        break;
      case 'face_home':
        page = HomeScreen();
        break;
      case 'age_gender':
        page = AgeGenderScreen();
        break;
      case 'face_recognition':
        page = FaceRecognitionScreen();
        break;
      case 'attributes':
        page = AttributesScreen();
        break;
      case 'home':
        // Already on home, just speak
        _voiceService.speak("You are on the home page");
        return;
    }

    if (page != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page!),
      );
    } else {
      _voiceService.speak("Cannot navigate to this page. Camera may not be available");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🤖 Smart Assistant', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // Voice Navigation Button
          IconButton(
            icon: Icon(
              _voiceService.isListening ? Icons.mic : Icons.mic_none,
              color: _isVoiceEnabled 
                  ? (_voiceService.isListening ? Colors.red : Colors.blue)
                  : Colors.grey,
            ),
            onPressed: (_isVoiceEnabled && !_isProcessing) ? _handleVoiceCommand : null,
            tooltip: _voiceService.isListening ? 'Listening...' : 'Voice Navigation',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // App Header
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[700]!, Colors.purple[700]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.accessibility_new, size: 64, color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    'Smart Assistant Hub',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'All-in-one accessibility solution',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            // Voice Navigation Info
            if (_isVoiceEnabled)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _voiceService.isListening 
                      ? Colors.red[900]?.withOpacity(0.3)
                      : Colors.blue[900]?.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _voiceService.isListening ? Colors.red : Colors.blue,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _voiceService.isListening ? Icons.mic : Icons.mic_none,
                      color: _voiceService.isListening ? Colors.red : Colors.blue,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _voiceService.isListening 
                                ? '🎤 Listening...' 
                                : 'Voice Navigation Active',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _voiceService.isListening
                                ? 'Speak your command now'
                                : 'Say "currency", "face detection", "wallet", etc.',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            SizedBox(height: 32),
            
            // Main Feature Sections
            Text(
              'Choose Feature',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            
            SizedBox(height: 16),
            
            // Currency & Bills Section
            _buildMainFeatureCard(
              context,
              icon: Icons.monetization_on,
              title: 'Currency & Bills',
              description: 'Scan currency, bills, and manage your wallet',
              gradient: [Colors.green[700]!, Colors.teal[700]!],
              features: [
                '💵 AR Currency Detection',
                '🧾 Bill Scanner',
                '💰 Smart Wallet',
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CurrencyBillsHome(),
                  ),
                );
              },
            ),
            
            SizedBox(height: 16),
            
            // Face Detection Section
            _buildMainFeatureCard(
              context,
              icon: Icons.face,
              title: 'Face Detection',
              description: 'Recognize faces, detect age, gender & attributes',
              gradient: [Colors.purple[700]!, Colors.pink[700]!],
              features: [
                '👤 Face Recognition',
                '🎭 Age & Gender Detection',
                '👁️ Facial Attributes',
              ],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HomeScreen(),
                  ),
                );
              },
            ),
            
            SizedBox(height: 24),
            
            // Info Section
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap cards or use voice to navigate',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isVoiceEnabled
          ? FloatingActionButton.extended(
              onPressed: (_isProcessing || _voiceService.isListening) ? null : _handleVoiceCommand,
              icon: Icon(
                _voiceService.isListening ? Icons.mic : Icons.mic_none,
              ),
              label: Text(
                _voiceService.isListening ? 'Listening...' : 'Voice Nav',
              ),
              backgroundColor: _voiceService.isListening 
                  ? Colors.red 
                  : (_isProcessing ? Colors.grey : Colors.blue),
            )
          : null,
    );
  }

  Widget _buildMainFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required List<Color> gradient,
    required List<String> features,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 40, color: Colors.white),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            description,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 24),
                  ],
                ),
                
                SizedBox(height: 16),
                Divider(color: Colors.white30),
                SizedBox(height: 8),
                
                // Features List
                ...features.map((feature) => Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white70, size: 20),
                      SizedBox(width: 8),
                      Text(
                        feature,
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                )).toList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}
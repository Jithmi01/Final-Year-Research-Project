// lib/main.dart - UNIFIED APP
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// Face Detection Imports
import 'screens/face_detection/home_screen.dart';

// Currency & Bills Imports  
import 'screens/currency_bills/currency_bills_home.dart';

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
        backgroundColor: Colors.grey[850],  // ✅ Capital C
        elevation: 0,
        centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[850],  // ✅ Capital C
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

class MasterHomePage extends StatelessWidget {
  const MasterHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🤖 Smart Assistant', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    builder: (context) => const  CurrencyBillsHome(),
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
                      'Tap on any card to access features with voice guidance',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
}
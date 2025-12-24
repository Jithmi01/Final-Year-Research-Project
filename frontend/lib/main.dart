// lib/main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// Import all pages
import 'ar_currency_detector_page.dart'; // NEW: AR Currency Detector

import 'wallet_scanner_page.dart';
import 'wallet_qa_page.dart';
import 'bill_scanner_page.dart';


// Your IP Address - CHANGE THIS!
const String YOUR_SERVER_IP = "192.168.8.143";
const String API_URL = "http://$YOUR_SERVER_IP:5000";

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Assistant',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[850],
          elevation: 0,
        ),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (cameras.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Error')),
        body: Center(
          child: Text(
            'No camera found on this device.',
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '🤖 Smart Assistant',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[700]!, Colors.blue[900]!],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.accessibility_new, size: 48, color: Colors.white),
                  SizedBox(height: 8),
                  Text(
                    'Choose a Tool',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Voice-guided assistance for daily tasks',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            // Section: Money Management
            _buildSectionHeader('💰 Money Management'),
            SizedBox(height: 12),
            
            _buildFeatureCard(
              context,
              icon: Icons.receipt_long,
              title: 'Bill Scanner',
              description: 'Scan bills and track expenses',
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BillScannerPage(camera: cameras.first),
                ),
              ),
            ),
            
            SizedBox(height: 12),
            
            
            
            // ⭐ NEW: AR Currency Detector - FEATURED!
            _buildFeatureCard(
              context,
              icon: Icons.camera_enhance,
              title: 'AR Currency Detector',
              description: 'Real-time currency detection with visual overlays',
              color: Colors.deepOrange,
              badge: 'NEW',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ARCurrencyDetectorPage(camera: cameras.first),
                ),
              ),
            ),
            
            SizedBox(height: 12),
            
            _buildFeatureCard(
              context,
              icon: Icons.account_balance_wallet,
              title: 'Wallet Scanner',
              description: 'Scan currency and add to wallet',
              color: Colors.teal,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WalletScannerPage(camera: cameras.first),
                ),
              ),
            ),
            
            SizedBox(height: 24),
            
            // Section: Information Access
            _buildSectionHeader('📄 Information Access'),
            SizedBox(height: 12),
            
            
            
          
            
            SizedBox(height: 12),
            
            _buildFeatureCard(
              context,
              icon: Icons.question_answer,
              title: 'Wallet Q&A',
              description: 'Ask about your finances',
              color: Colors.indigo,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WalletQAPage(),
                ),
              ),
            ),
            
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              SizedBox(width: 16),
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
                          ),
                        ),
                        if (badge != null) ...[
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
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
                    SizedBox(height: 4),
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
              Icon(Icons.arrow_forward_ios, color: Colors.grey[600]),
            ],
          ),
        ),
      ),
    );
  }
}
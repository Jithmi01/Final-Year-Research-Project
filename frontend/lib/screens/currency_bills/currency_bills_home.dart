// lib/screens/currency_bills/currency_bills_home.dart
import 'package:flutter/material.dart';
import '../../main.dart';
import '../../pages/currency/ar_currency_detector_page.dart';
import '../../pages/bills/bill_scanner_page.dart';
import '../../pages/smart_wallet/wallet_scanner_page.dart';
import '../../pages/smart_wallet/wallet_qa_page.dart';

class CurrencyBillsHome extends StatelessWidget {
  const CurrencyBillsHome({Key? key}) : super(key: key);

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
          '💵 Currency & Bills',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                  colors: [Colors.green[700]!, Colors.teal[700]!],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.monetization_on, size: 48, color: Colors.white),
                  SizedBox(height: 8),
                  Text(
                    'Currency & Bills Features',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Voice-guided money management',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            // Section: Currency Detection
            _buildSectionHeader('💵 Currency Detection'),
            SizedBox(height: 12),
            
            _buildFeatureCard(
              context,
              icon: Icons.camera_enhance,
              title: 'AR Currency Detector',
              description: 'Real-time currency detection with AR overlays',
              color: Colors.deepOrange,
              badge: 'NEW',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ARCurrencyDetectorPage(camera: cameras.first),
                ),
              ),
            ),
            
            SizedBox(height: 24),
            
            // Section: Bills Management
            _buildSectionHeader('🧾 Bills Management'),
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
            
            SizedBox(height: 24),
            
            // Section: Smart Wallet
            _buildSectionHeader('💰 Smart Wallet'),
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
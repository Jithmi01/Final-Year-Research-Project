// lib/bill_scanner_page.dart
// WITH FLASHLIGHT TOGGLE

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import '../../main.dart';
import '../../widgets/voice_navigation_widget.dart';

class BillScannerPage extends StatefulWidget {
  final CameraDescription camera;
  const BillScannerPage({Key? key, required this.camera}) : super(key: key);

  @override
  _BillScannerPageState createState() => _BillScannerPageState();
}

class _BillScannerPageState extends State<BillScannerPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  FlutterTts flutterTts = FlutterTts();
  
  bool _isProcessing = false;
  bool _cameraInitialized = false;
  bool _isFlashOn = false; // ⭐ Flash state
  double _currentBalance = 0.0;
  
  String _vendor = '';
  String _address = '';
  String _date = '';
  String _totalAmount = '';
  String _cashAmount = '';
  String _changeAmount = '';
  String _category = '';
  
  String _statusMessage = "Ready to scan";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _setupTts();
    _fetchBalance();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    
    _initializeControllerFuture = _controller.initialize();
    
    try {
      await _initializeControllerFuture;
      
      if (mounted) {
        await _controller.setFlashMode(FlashMode.off);
        await _controller.setFocusMode(FocusMode.auto);
        await _controller.setExposureMode(ExposureMode.auto);
        
        setState(() {
          _cameraInitialized = true;
        });
        
        print("[CAMERA] Initialized: ${_controller.value.previewSize}");
      }
    } catch (e) {
      print("[CAMERA] Error: $e");
    }
  }

  // ⭐ Toggle flashlight
  Future<void> _toggleFlash() async {
    if (!_cameraInitialized) return;
    
    try {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
      
      if (_isFlashOn) {
        await _controller.setFlashMode(FlashMode.torch);
        _speak("Flash on");
        print("[FLASH] ON");
      } else {
        await _controller.setFlashMode(FlashMode.off);
        _speak("Flash off");
        print("[FLASH] OFF");
      }
    } catch (e) {
      print("[FLASH] Error: $e");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Flash not available on this device'),
          duration: Duration(seconds: 2),
        ),
      );
      
      setState(() {
        _isFlashOn = false;
      });
    }
  }

  void _setupTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await flutterTts.speak(text);
  }

  Future<void> _fetchBalance() async {
    try {
      final response = await http.get(Uri.parse("$API_URL/get_wallet_balance"));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          _currentBalance = data['balance']?.toDouble() ?? 0.0;
        });
      }
    } catch (e) {
      print("Balance error: $e");
    }
  }

  @override
  void dispose() {
    // Turn off flash before disposing
    if (_isFlashOn) {
      _controller.setFlashMode(FlashMode.off);
    }
    _controller.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _scanBill() async {
    if (_isProcessing || !_cameraInitialized || !mounted) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = "Capturing...";
      _clearResults();
    });
    
    _speak("Scanning");

    try {
      print("[SCAN] Capturing...");
      final image = await _controller.takePicture();
      final File imageFile = File(image.path);
      
      final fileSize = await imageFile.length();
      print("[SCAN] Image size: ${fileSize} bytes");

      setState(() {
        _statusMessage = "Sending to server...";
      });

      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$API_URL/scan_bill_display_only"),
      );
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      print("[SCAN] Uploading...");
      final uploadStart = DateTime.now();
      
      var streamedResponse = await request.send().timeout(
        Duration(seconds: 30),
        onTimeout: () => throw Exception('Request timeout'),
      );
      
      final uploadTime = DateTime.now().difference(uploadStart).inMilliseconds;
      print("[SCAN] Upload took: ${uploadTime}ms");
      
      var response = await http.Response.fromStream(streamedResponse);
      print("[SCAN] Response: ${response.statusCode}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          var billInfo = data['bill_info'];
          
          if (!mounted) return;
          setState(() {
            _vendor = billInfo['vendor'] ?? 'Unknown';
            _address = billInfo['address'] ?? '';
            _date = billInfo['date'] ?? '';
            _totalAmount = billInfo['total_amount']?.toString() ?? '0.00';
            _cashAmount = billInfo['cash']?.toString() ?? '';
            _changeAmount = billInfo['change']?.toString() ?? '';
            _category = billInfo['category'] ?? 'General';
            _statusMessage = "Scan complete";
          });
          
          print("[SCAN] ✓ Success: $_vendor, Total:$_totalAmount, Cash:$_cashAmount, Change:$_changeAmount");
          
          _speak(_generateAnnouncement());
          
          if (_totalAmount != '0.00' && _totalAmount != '0.0' && _totalAmount.isNotEmpty) {
            await Future.delayed(Duration(milliseconds: 800));
            _showAddToWalletDialog();
          }
        } else {
          throw Exception(data['error'] ?? 'Failed to scan');
        }
      } else {
        var errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Server error ${response.statusCode}');
      }
    } catch (e) {
      print("[SCAN] ✗ Error: $e");
      
      if (!mounted) return;
      setState(() {
        _statusMessage = "Scan failed - Try again";
      });
      
      _speak("Scan failed. Try again.");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Scan failed: ${e.toString().replaceAll('Exception:', '').trim()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _showAddToWalletDialog() async {
    bool? add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.blue),
            SizedBox(width: 8),
            Text('Add to Wallet?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add this expense to your wallet?'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vendor: $_vendor', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                    'Total: Rs. $_totalAmount',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  if (_cashAmount.isNotEmpty && _cashAmount != '0.00') ...[
                    SizedBox(height: 4),
                    Text('Cash Paid: Rs. $_cashAmount', style: TextStyle(color: Colors.green[700])),
                  ],
                  if (_changeAmount.isNotEmpty && _changeAmount != '0.00') ...[
                    SizedBox(height: 4),
                    Text('Change: Rs. $_changeAmount', style: TextStyle(color: Colors.orange[700])),
                  ],
                  SizedBox(height: 4),
                  Text('Category: $_category', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Current Balance: Rs. ${_currentBalance.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              'After: Rs. ${(_currentBalance - double.parse(_totalAmount)).toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Add Expense'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (add == true) {
      await _addToWallet();
    }
  }

  Future<void> _addToWallet() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Adding to wallet...";
    });

    try {
      double amount = double.parse(_totalAmount);
      
      final response = await http.post(
        Uri.parse("$API_URL/add_wallet_transaction"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amount,
          'type': 'expense',
          'category': _category,
          'description': 'Bill from $_vendor',
        }),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        double newBalance = data['new_balance']?.toDouble() ?? _currentBalance;
        
        setState(() {
          _currentBalance = newBalance;
          _statusMessage = "Added to wallet";
        });
        
        _speak("Added. Balance: ${newBalance.toStringAsFixed(0)} rupees.");
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Added! Balance: Rs. ${newBalance.toStringAsFixed(2)}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print("[WALLET] Error: $e");
      _speak("Failed to add");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _clearResults() {
    _vendor = '';
    _address = '';
    _date = '';
    _totalAmount = '';
    _cashAmount = '';
    _changeAmount = '';
    _category = '';
  }

  String _generateAnnouncement() {
    List<String> parts = [];
    
    if (_vendor.isNotEmpty && _vendor != 'Unknown') {
      parts.add(_vendor);
    }
    
    if (_totalAmount.isNotEmpty && _totalAmount != '0.00') {
      parts.add("Total: $_totalAmount rupees");
    }
    
    if (_cashAmount.isNotEmpty && _cashAmount != '0.00') {
      parts.add("Cash paid: $_cashAmount rupees");
    }
    
    if (_changeAmount.isNotEmpty && _changeAmount != '0.00') {
      parts.add("Change: $_changeAmount rupees");
    }
    
    if (_category.isNotEmpty && _category != 'General') {
      parts.add("Category: $_category");
    }
    
    return parts.isEmpty ? "No information found" : parts.join(". ");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bill Scanner'),
        actions: [
          // ⭐ Flashlight button in AppBar
          IconButton(
            icon: Icon(
              _isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: _isFlashOn ? Colors.yellow : Colors.white,
            ),
            onPressed: _cameraInitialized ? _toggleFlash : null,
            tooltip: _isFlashOn ? 'Turn off flash' : 'Turn on flash',
          ),
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: VoiceNavigationWidget(currentPage: 'bill_scanner'),
          ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Chip(
              label: Text('Rs. ${_currentBalance.toStringAsFixed(2)}'),
              backgroundColor: Colors.green,
              labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera
          Expanded(
            flex: 3,
            child: _cameraInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.width * _controller.value.aspectRatio,
                              child: CameraPreview(_controller),
                            ),
                          ),
                        ),
                      ),
                      
                      if (_isProcessing)
                        Container(
                          color: Colors.black54,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 16),
                                Text(
                                  _statusMessage,
                                  style: TextStyle(color: Colors.white, fontSize: 18),
                                ),
                              ],
                            ),
                          ),
                        ),
                      
                      if (!_isProcessing)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: FramePainter(),
                          ),
                        ),
                      
                      // ⭐ Floating flash button on camera
                      if (!_isProcessing)
                        Positioned(
                          top: 20,
                          right: 20,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: _isFlashOn ? Colors.yellow : Colors.black54,
                            onPressed: _toggleFlash,
                            child: Icon(
                              _isFlashOn ? Icons.flash_on : Icons.flash_off,
                              color: _isFlashOn ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(child: CircularProgressIndicator()),
          ),
          
          // Status
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.black87,
            child: Row(
              children: [
                Icon(_isProcessing ? Icons.hourglass_empty : Icons.check_circle,
                     color: _isProcessing ? Colors.orange : Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(_statusMessage, 
                             style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ],
            ),
          ),
          
          // Results
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[900],
              padding: EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Bill Info', 
                             style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        if (_totalAmount.isNotEmpty && _totalAmount != '0.00')
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Total: Rs. $_totalAmount',
                                     style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              if (_cashAmount.isNotEmpty && _cashAmount != '0.00') ...[
                                SizedBox(height: 2),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Cash: Rs. $_cashAmount',
                                       style: TextStyle(color: Colors.white, fontSize: 10)),
                                ),
                              ],
                              if (_changeAmount.isNotEmpty && _changeAmount != '0.00') ...[
                                SizedBox(height: 2),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('Change: Rs. $_changeAmount',
                                       style: TextStyle(color: Colors.white, fontSize: 10)),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _buildInfoRow('Vendor', _vendor, Icons.store, Colors.blue),
                    SizedBox(height: 6),
                    _buildInfoRow('Address', _address, Icons.location_on, Colors.red),
                    SizedBox(height: 6),
                    _buildInfoRow('Category', _category, Icons.category, Colors.purple),
                    SizedBox(height: 6),
                    _buildInfoRow('Date', _date, Icons.calendar_today, Colors.orange),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_isProcessing || !_cameraInitialized) ? null : _scanBill,
        icon: Icon(Icons.camera_alt),
        label: Text(_isProcessing ? 'Scanning...' : 'SCAN'),
        backgroundColor: (_isProcessing || !_cameraInitialized) ? Colors.grey : Colors.green,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, Color color) {
    bool hasValue = value.isNotEmpty && value != 'Unknown' && value != 'General';
    
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            hasValue ? value : 'Not detected',
            style: TextStyle(
              color: hasValue ? Colors.white : Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.85,
      height: size.height * 0.75,
    );
    
    final len = 40.0;
    
    // Draw corner brackets
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, len), paint);
    
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, len), paint);
    
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -len), paint);
    
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -len), paint);
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Align bill within frame',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 4,
              color: Colors.black87,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        rect.top - 40,
      ),
    );
  }

  @override
  bool shouldRepaint(FramePainter oldDelegate) => false;
}
// lib/pages/bills/bill_scanner_page.dart
// COMPLETE FINAL VERSION - WITH MENU ITEMS + REAL-TIME CAMERA GUIDANCE

import 'dart:async';
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
  bool _isFlashOn = false;
  double _currentBalance = 0.0;

  // Bill data
  String _vendor = '';
  String _address = '';
  String _date = '';
  String _totalAmount = '';
  String _cashAmount = '';
  String _changeAmount = '';
  String _category = '';
  List<dynamic> _menuItems = [];
  String _statusMessage = "Ready to scan";

  // CAMERA GUIDANCE - Quality checking
  Timer? _qualityCheckTimer;
  bool _isCheckingQuality = false;
  double _qualityScore = 0;
  String _qualityGuidance = "Position bill in camera view";
  bool _canScan = false;
  
  // Quality indicators
  bool _brightnessOk = false;
  bool _sharpnessOk = false;
  bool _sizeOk = false;
  bool _contrastOk = false;
  
  // Bill detection indicators
  bool _billDetected = false;
  bool _billCentered = false;
  bool _billCorrectSize = false;
  bool _billLevel = false;
  String _direction = 'none';
  
  // Camera Guidance Toggle
  bool _guidanceEnabled = true; // ON by default  // 'left', 'right', 'up', 'down', 'closer', 'farther', 'center'
  
  // Voice announcement tracking (avoid repetition)
  String _lastVoicePrompt = "";
  DateTime _lastVoiceTime = DateTime.now();

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

        print("[CAMERA] Initialized");
        
        // START REAL-TIME QUALITY CHECKING
        _startQualityChecking();
      }
    } catch (e) {
      print("[CAMERA] Error: $e");
    }
  }

  void _startQualityChecking() {
    // Check quality every 2 seconds (only if guidance enabled)
    _qualityCheckTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (_cameraInitialized && !_isProcessing && mounted && _guidanceEnabled) {
        _checkImageQuality();
      }
    });
  }

  Future<void> _checkImageQuality() async {
    if (_isCheckingQuality) return;

    setState(() {
      _isCheckingQuality = true;
    });

    try {
      // Capture preview frame
      final image = await _controller.takePicture();
      final File imageFile = File(image.path);

      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$API_URL/check_image_quality"),
      );
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      var streamedResponse = await request.send().timeout(
        Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Quality check timeout');
        },
      );

      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        if (data['success'] == true) {
          if (!mounted) return;

          setState(() {
            _qualityScore = data['quality_score']?.toDouble() ?? 0;
            _qualityGuidance = data['voice_prompt'] ?? '';
            _canScan = data['is_acceptable'] ?? false;
            
            var checks = data['checks'] ?? {};
            _brightnessOk = checks['brightness_ok'] ?? false;
            _sharpnessOk = checks['sharpness_ok'] ?? false;
            _sizeOk = checks['size_ok'] ?? false;
            _contrastOk = checks['contrast_ok'] ?? false;
            
            // Bill detection data
            _billDetected = data['bill_detected'] ?? false;
            _billCentered = data['bill_centered'] ?? false;
            _billCorrectSize = data['bill_correct_size'] ?? false;
            _billLevel = data['bill_level'] ?? false;
            _direction = data['direction'] ?? 'none';
          });

          // Announce guidance if it changed (avoid repetition)
          if (_qualityGuidance.isNotEmpty && 
              _qualityGuidance != _lastVoicePrompt &&
              DateTime.now().difference(_lastVoiceTime).inSeconds > 3) {
            _speak(_qualityGuidance);
            _lastVoicePrompt = _qualityGuidance;
            _lastVoiceTime = DateTime.now();
          }
        }
      }

      // Clean up temp file
      await imageFile.delete();

    } catch (e) {
      print("[QUALITY CHECK] Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingQuality = false;
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (!_cameraInitialized) return;

    try {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });

      if (_isFlashOn) {
        await _controller.setFlashMode(FlashMode.torch);
        _speak("Flash on");
      } else {
        await _controller.setFlashMode(FlashMode.off);
        _speak("Flash off");
      }
    } catch (e) {
      print("[FLASH] Error: $e");
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
    await flutterTts.stop(); // Stop any ongoing speech
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
    _qualityCheckTimer?.cancel(); // Cancel quality checking timer
    if (_isFlashOn) {
      _controller.setFlashMode(FlashMode.off);
    }
    _controller.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _scanBill() async {
    if (_isProcessing || !_cameraInitialized || !mounted) return;

    // ONLY check quality if guidance is enabled
    if (_guidanceEnabled) {
      // CHECK QUALITY BEFORE SCANNING
      if (!_canScan && _qualityScore > 0) {
        _speak("Image quality too poor. $_qualityGuidance");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ $_qualityGuidance'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return; // Don't proceed with scan
      }
    }
    // If guidance OFF, skip all quality checks and scan freely

    setState(() {
      _isProcessing = true;
      _statusMessage = "Capturing...";
      _clearResults();
    });

    _speak("Scanning");

          try {
      final image = await _controller.takePicture();
      final File imageFile = File(image.path);

      setState(() {
        _statusMessage = "Processing...";
      });

      // Choose endpoint based on guidance setting
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(_guidanceEnabled 
            ? "$API_URL/scan_bill_with_guidance"  // With quality check
            : "$API_URL/scan_bill_display_only"),  // Direct scan, no quality check
      );
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      var streamedResponse = await request.send().timeout(
        Duration(seconds: 90),
        onTimeout: () => throw Exception('Request timeout - please try again'),
      );

      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        print("[SCAN DEBUG] Full response: ${jsonEncode(data)}");

        if (data['success'] == true) {
          var billInfo = data['bill_info'];

          print("[SCAN DEBUG] Menu items: ${billInfo['menu_items']}");

          if (!mounted) return;
          setState(() {
            _vendor = billInfo['vendor'] ?? 'Unknown';
            _address = billInfo['address'] ?? '';
            _date = billInfo['date'] ?? '';
            _totalAmount = billInfo['total_amount']?.toString() ?? '0.00';
            _cashAmount = billInfo['cash']?.toString() ?? '';
            _changeAmount = billInfo['change']?.toString() ?? '';
            _category = billInfo['category'] ?? 'General';
            _menuItems = billInfo['menu_items'] ?? [];
            _statusMessage = "Scan complete";
          });

          print("[SCAN] ✓ Success: $_vendor, Total:$_totalAmount, Items:${_menuItems.length}");

          // Use voice prompt from server if available
          String announcement = data['voice_prompt'] ?? _generateAnnouncement();
          _speak(announcement);

          if (_totalAmount != '0.00' && _totalAmount != '0.0' && _totalAmount.isNotEmpty) {
            await Future.delayed(Duration(milliseconds: 800));
            _showBillDetailsDialog();
          }
        } else {
          throw Exception(data['error'] ?? 'Failed to scan');
        }
      } else {
        var data = jsonDecode(response.body);
        
        // Handle quality issues from server
        if (data['should_retry'] == true) {
          var qualityCheck = data['quality_check'];
          _speak(qualityCheck['voice_prompt']);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('❌ ${data['error']}'),
                  SizedBox(height: 4),
                  Text(
                    qualityCheck['voice_prompt'],
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          throw Exception(data['error'] ?? 'Server error');
        }
      }
    } catch (e) {
      print("[SCAN] ✗ Error: $e");

      if (!mounted) return;
      setState(() {
        _statusMessage = "Scan failed";
      });

      _speak("Scan failed. Try again.");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
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

  Future<void> _showBillDetailsDialog() async {
    bool? add = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade700, Colors.blue.shade500],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.receipt_long, color: Colors.white, size: 28),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bill Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Review before adding',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vendor Card
                      _buildInfoCard(
                        icon: Icons.store,
                        iconColor: Colors.blue,
                        title: 'Vendor Information',
                        children: [
                          _buildDetailRow('Name', _vendor, bold: true),
                          if (_address.isNotEmpty) ...[
                            SizedBox(height: 8),
                            _buildDetailRow('Address', _address),
                          ],
                          if (_date.isNotEmpty) ...[
                            SizedBox(height: 8),
                            _buildDetailRow('Date', _date),
                          ],
                          SizedBox(height: 8),
                          _buildDetailRow('Category', _category, valueColor: Colors.purple.shade700),
                        ],
                      ),

                      // Menu Items Card
                      if (_menuItems.isNotEmpty) ...[
                        SizedBox(height: 16),
                        _buildMenuItemsCard(),
                      ],

                      // Payment Summary Card
                      SizedBox(height: 16),
                      _buildPaymentSummaryCard(),

                      // Balance Impact Card
                      SizedBox(height: 16),
                      _buildBalanceImpactCard(),
                    ],
                  ),
                ),
              ),

              // Actions
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.close),
                        label: Text('Cancel'),
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.add_card),
                        label: Text('Add to Wallet'),
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (add == true) {
      await _addToWallet();
    }
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMenuItemsCard() {
    double subtotal = 0;
    for (var item in _menuItems) {
      double price = (item['price_numeric'] ?? 0.0).toDouble();
      int count = (item['count_numeric'] ?? 1);
      subtotal += price * count;
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.restaurant_menu, color: Colors.orange.shade700, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                'Menu Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_menuItems.length} items',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Items List
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _menuItems.length,
            separatorBuilder: (context, index) => Divider(height: 24),
            itemBuilder: (context, index) {
              var item = _menuItems[index];
              String name = item['name'] ?? 'Item ${index + 1}';

              double price = 0.0;
              if (item['price_numeric'] != null) {
                price = (item['price_numeric'] is int)
                    ? (item['price_numeric'] as int).toDouble()
                    : item['price_numeric'];
              } else if (item['price'] != null) {
                try {
                  price = double.parse(item['price'].toString());
                } catch (e) {
                  price = 0.0;
                }
              }

              int count = 1;
              if (item['count_numeric'] != null) {
                count = (item['count_numeric'] is int)
                    ? item['count_numeric']
                    : int.tryParse(item['count_numeric'].toString()) ?? 1;
              }

              double itemTotal = price * count;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        if (count > 1 || price > 0) ...[
                          SizedBox(height: 4),
                          Row(
                            children: [
                              if (count > 1)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Qty: $count',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              if (count > 1 && price > 0) SizedBox(width: 6),
                              if (price > 0)
                                Text(
                                  'Rs.${price.toStringAsFixed(2)} each',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    'Rs.${itemTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              );
            },
          ),

          if (_menuItems.length > 1) ...[
            SizedBox(height: 12),
            Divider(),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Items Subtotal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  'Rs.${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentSummaryCard() {
    return _buildInfoCard(
      icon: Icons.payment,
      iconColor: Colors.green,
      title: 'Payment Summary',
      children: [
        _buildDetailRow(
          'Total Amount',
          'Rs. $_totalAmount',
          bold: true,
          valueColor: Colors.red.shade700,
          fontSize: 16,
        ),
        if (_cashAmount.isNotEmpty && _cashAmount != '0.00') ...[
          SizedBox(height: 12),
          _buildDetailRow('Cash Paid', 'Rs. $_cashAmount', valueColor: Colors.green.shade700),
        ],
        if (_changeAmount.isNotEmpty && _changeAmount != '0.00') ...[
          SizedBox(height: 8),
          _buildDetailRow('Change', 'Rs. $_changeAmount', valueColor: Colors.orange.shade700),
        ],
      ],
    );
  }

  Widget _buildBalanceImpactCard() {
    double totalAmount = double.tryParse(_totalAmount) ?? 0.0;
    double newBalance = _currentBalance - totalAmount;
    bool isNegative = newBalance < 0;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isNegative
              ? [Colors.red.shade50, Colors.red.shade100]
              : [Colors.blue.shade50, Colors.blue.shade100],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNegative ? Colors.red.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isNegative ? Icons.warning : Icons.account_balance_wallet,
                color: isNegative ? Colors.red.shade700 : Colors.blue.shade700,
              ),
              SizedBox(width: 8),
              Text(
                'Balance Impact',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current Balance:'),
              Text(
                'Rs. ${_currentBalance.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('After Expense:'),
              Text(
                'Rs. ${newBalance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isNegative ? Colors.red.shade700 : Colors.green.shade700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (isNegative) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.red.shade700),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Warning: This will make your balance negative',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
    double fontSize = 14,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.grey.shade700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? Colors.grey.shade900,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addToWallet() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Adding...";
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
          'description': 'Bill from $_vendor${_menuItems.isNotEmpty ? " (${_menuItems.length} items)" : ""}',
        }),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        double newBalance = data['new_balance']?.toDouble() ?? _currentBalance;

        setState(() {
          _currentBalance = newBalance;
          _statusMessage = "Added successfully";
        });

        _speak("Added. Balance: ${newBalance.toStringAsFixed(0)} rupees.");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Bill added! New balance: Rs. ${newBalance.toStringAsFixed(2)}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print("[WALLET] Error: $e");
      _speak("Failed to add");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add bill: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Ready to scan";
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
    _menuItems = [];
  }

  String _generateAnnouncement() {
    List<String> parts = [];

    if (_vendor.isNotEmpty && _vendor != 'Unknown') {
      parts.add(_vendor);
    }

    if (_menuItems.isNotEmpty) {
      parts.add("${_menuItems.length} items");
    }

    if (_totalAmount.isNotEmpty && _totalAmount != '0.00') {
      parts.add("Total: $_totalAmount rupees");
    }

    return parts.isEmpty ? "No information found" : parts.join(". ");
  }

  Color _getQualityColor() {
    if (_qualityScore >= 80) return Colors.green;
    if (_qualityScore >= 60) return Colors.orange;
    return Colors.red;
  }

  Widget _buildQualityIndicator(String label, bool isOk) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOk ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOk ? Icons.check : Icons.close, color: Colors.white, size: 14),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionalArrow(String direction) {
    IconData arrowIcon;
    String text;
    
    switch (direction) {
      case 'left':
        arrowIcon = Icons.arrow_back;
        text = '← MOVE LEFT';
        break;
      case 'right':
        arrowIcon = Icons.arrow_forward;
        text = 'MOVE RIGHT →';
        break;
      case 'up':
        arrowIcon = Icons.arrow_upward;
        text = '↑ MOVE UP';
        break;
      case 'down':
        arrowIcon = Icons.arrow_downward;
        text = '↓ MOVE DOWN';
        break;
      case 'closer':
        arrowIcon = Icons.zoom_in;
        text = 'MOVE CLOSER';
        break;
      case 'farther':
        arrowIcon = Icons.zoom_out;
        text = 'MOVE BACK';
        break;
      case 'rotate':
        arrowIcon = Icons.rotate_right;
        text = 'ROTATE BILL';
        break;
      default:
        return SizedBox.shrink();
    }
    
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            arrowIcon,
            color: Colors.white,
            size: 60,
          ),
          SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bill Scanner'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: VoiceNavigationWidget(currentPage: 'bill_scanner'),
          ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Chip(
              avatar: Icon(Icons.account_balance_wallet, color: Colors.white, size: 16),
              label: Text('Rs. ${_currentBalance.toStringAsFixed(2)}'),
              backgroundColor: Colors.green,
              labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // CAMERA PREVIEW WITH REAL-TIME QUALITY OVERLAY
          Expanded(
            flex: 2,
            child: _cameraInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller),
                      
                      // GUIDANCE TOGGLE BUTTON (Top-left corner)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _guidanceEnabled = !_guidanceEnabled;
                              });
                              _speak(_guidanceEnabled ? "Guidance on" : "Guidance off");
                              
                              // Reset indicators when turning off
                              if (!_guidanceEnabled) {
                                setState(() {
                                  _qualityScore = 0;
                                  _qualityGuidance = "Guidance disabled";
                                  _canScan = true; // Allow scanning without checks
                                });
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _guidanceEnabled 
                                    ? Colors.blue.withOpacity(0.9) 
                                    : Colors.grey.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _guidanceEnabled 
                                        ? Icons.visibility 
                                        : Icons.visibility_off,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    _guidanceEnabled ? 'Guide ON' : 'Guide OFF',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // QUALITY SCORE INDICATOR (only show if guidance enabled)
                      if (_guidanceEnabled)
                        Positioned(
                          top: 70,
                          left: 16,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _getQualityColor().withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _canScan ? Icons.check_circle : Icons.warning,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Quality: ${_qualityScore.toInt()}%',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      
                      // QUALITY CHECKS (only show if guidance enabled)
                      if (_guidanceEnabled)
                        Positioned(
                          top: 114,
                          left: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildQualityIndicator('Bill', _billDetected),
                              SizedBox(height: 4),
                              _buildQualityIndicator('Centered', _billCentered),
                              SizedBox(height: 4),
                              _buildQualityIndicator('Size', _billCorrectSize),
                              SizedBox(height: 4),
                              _buildQualityIndicator('Level', _billLevel),
                            ],
                          ),
                        ),
                      
                      // DIRECTIONAL ARROW (only show if guidance enabled)
                      if (_guidanceEnabled && _billDetected && !_canScan && _direction != 'none' && _direction != 'center')
                        Positioned(
                          top: MediaQuery.of(context).size.height * 0.25,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _buildDirectionalArrow(_direction),
                          ),
                        ),
                      
                      // FLASH TOGGLE (Top-right)
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
                      
                      // GUIDANCE MESSAGE (only show if guidance enabled)
                      if (_guidanceEnabled)
                        Positioned(
                          bottom: 20,
                          left: 20,
                          right: 20,
                          child: Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _qualityGuidance,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      
                      // PROCESSING OVERLAY
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
                    ],
                  )
                : Center(child: CircularProgressIndicator()),
          ),

          // STATUS BAR
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.black87,
            child: Row(
              children: [
                Icon(
                  _isProcessing ? Icons.hourglass_empty : Icons.check_circle,
                  color: _isProcessing ? Colors.orange : Colors.green,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                if (_menuItems.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_menuItems.length} items',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // RESULTS PREVIEW
          Expanded(
            flex: 1,
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
                        Text(
                          'Bill Preview',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (_totalAmount.isNotEmpty && _totalAmount != '0.00')
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Rs. $_totalAmount',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _buildInfoRow('Vendor', _vendor, Icons.store, Colors.blue),
                    SizedBox(height: 6),
                    _buildInfoRow('Category', _category, Icons.category, Colors.purple),
                    if (_menuItems.isNotEmpty) ...[
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.restaurant_menu, color: Colors.orange, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Items (${_menuItems.length})',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            ..._menuItems.take(3).map((item) {
                              final name = item['name'] ?? 'Item';
                              final price = (item['price_numeric'] ?? 0.0).toDouble();
                              final count = (item['count_numeric'] ?? 1);

                              return Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Text('• ', style: TextStyle(color: Colors.white70)),
                                    Expanded(
                                      child: Text(
                                        count > 1 ? '$name x$count' : name,
                                        style: TextStyle(color: Colors.white70, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      'Rs.${(price * count).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            if (_menuItems.length > 3)
                              Text(
                                '+ ${_menuItems.length - 3} more',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan_button', // Fix hero tag conflict
        onPressed: (_isProcessing || !_cameraInitialized) ? null : _scanBill,
        icon: Icon(_isProcessing ? Icons.hourglass_empty : Icons.camera_alt),
        label: Text(_isProcessing ? 'Scanning...' : 'SCAN BILL'),
        backgroundColor: (_isProcessing || !_cameraInitialized) 
            ? Colors.grey 
            : (_canScan ? Colors.green : Colors.orange),
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
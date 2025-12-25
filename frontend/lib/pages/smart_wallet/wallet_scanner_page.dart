// lib/wallet_scanner_page.dart (Updated with Savings Goal Feedback)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import '../../main.dart';
import '../../widgets/voice_navigation_widget.dart';

class WalletScannerPage extends StatefulWidget {
  final CameraDescription camera;
  const WalletScannerPage({Key? key, required this.camera}) : super(key: key);

  @override
  _WalletScannerPageState createState() => _WalletScannerPageState();
}

class _WalletScannerPageState extends State<WalletScannerPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  FlutterTts flutterTts = FlutterTts();
  String _statusMessage = "Press button to scan currency";
  bool _isProcessing = false;
  double _currentBalance = 0.0;
  
  // Savings Goal tracking
  Map<String, dynamic>? _activeGoal;
  bool _hasGoal = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera, 
      ResolutionPreset.medium, 
      enableAudio: false
    );
    _initializeControllerFuture = _controller.initialize();
    _setupTts();
    _fetchBalance();
    _checkActiveGoal(); // Check for active savings goal
  }

  void _setupTts() async {
    await flutterTts.setLanguage("en-LK");
    await flutterTts.setSpeechRate(0.5);
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
      print("Error fetching balance: $e");
    }
  }

  Future<void> _checkActiveGoal() async {
    try {
      final response = await http.get(Uri.parse("$API_URL/get_active_goal"));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        setState(() {
          _hasGoal = data['has_goal'] ?? false;
          _activeGoal = data['goal'];
        });
      }
    } catch (e) {
      print("Error checking goal: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scanAndProcessCurrency() async {
    if (_isProcessing) return;

    try {
      await _initializeControllerFuture;
      setState(() {
        _isProcessing = true;
        _statusMessage = "Scanning...";
      });
      _speak("Scanning currency.");

      final image = await _controller.takePicture();
      final File imageFile = File(image.path);

      var request = http.MultipartRequest(
        'POST', 
        Uri.parse("$API_URL/detect_currency")
      );
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path)
      );

      print("Sending image for currency detection...");
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      print("Detection Response: ${response.statusCode}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        List<dynamic> detectedItems = data['detected_items'] ?? [];

        if (detectedItems.isNotEmpty) {
          var item = detectedItems[0];
          double amount = item['amount']?.toDouble() ?? 0.0;
          String name = item['name'] ?? 'Unknown currency';

          if (amount > 0) {
            _speak("Detected $name. Amount is $amount rupees.");
            setState(() {
              _statusMessage = "Detected: $name (Rs. $amount)";
            });
            
            bool? added = await _showAddTransactionDialog(amount, name);
            
            if (added == true) {
              await _fetchBalance();
              await _checkActiveGoal();
              setState(() {
                _statusMessage = "Transaction Added! Balance: Rs. ${_currentBalance.toStringAsFixed(2)}";
              });
            } else {
              setState(() {
                _statusMessage = "Scan cancelled. Ready for next scan.";
              });
            }
          } else {
            _speak("Detected currency, but couldn't read the amount.");
            setState(() {
              _statusMessage = "Couldn't read amount. Try again.";
            });
          }
        } else {
          _speak("No currency detected in the image.");
          setState(() {
            _statusMessage = "No currency found. Aim better!";
          });
        }
      } else {
        throw Exception('Failed to detect currency: ${response.body}');
      }
    } catch (e) {
      print("Error during scan: $e");
      _speak("Error during scan. Please try again.");
      setState(() {
        _statusMessage = "Error during scan.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<bool?> _showAddTransactionDialog(double amount, String name) async {
    String? transactionType;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Add Transaction?'),
          content: Text('Add Rs. $amount ($name) to your wallet?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
                _speak("Cancelled.");
              },
            ),
            TextButton(
              child: Text('Add as INCOME'),
              onPressed: () {
                transactionType = 'income';
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Add as EXPENSE'),
              onPressed: () {
                transactionType = 'expense';
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );

    if (transactionType != null) {
      _speak("Adding transaction as $transactionType.");
      setState(() {
        _isProcessing = true;
        _statusMessage = "Adding transaction...";
      });
      return await _addTransactionAPI(amount, transactionType!, name);
    }
    return false;
  }

  Future<bool> _addTransactionAPI(
    double amount, 
    String type, 
    String currencyName
  ) async {
    try {
      final response = await http.post(
        Uri.parse("$API_URL/add_wallet_transaction"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amount,
          'type': type,
          'category': 'Currency Scan',
          'description': 'Scanned $currencyName',
        }),
      );

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        double newBalance = data['new_balance']?.toDouble() ?? _currentBalance;
        
        // Get goal feedback if available
        String goalFeedback = data['goal_feedback'] ?? '';
        Map<String, dynamic>? goalInfo = data['goal_info'];
        
        setState(() {
          _currentBalance = newBalance;
          if (goalInfo != null) {
            _activeGoal = goalInfo;
            _hasGoal = true;
          }
        });
        
        // Speak goal feedback if available
        if (goalFeedback.isNotEmpty) {
          _speak(goalFeedback);
        } else {
          _speak(
            "Transaction added successfully. New balance is ${newBalance.toStringAsFixed(2)} rupees."
          );
        }
        
        return true;
      } else {
        throw Exception('Failed to add transaction: ${response.body}');
      }
    } catch (e) {
      print("Error adding transaction via API: $e");
      _speak("Sorry, there was an error adding the transaction.");
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wallet Scanner'),
        actions: [
          if (_hasGoal)
            IconButton(
              icon: Icon(Icons.savings),
              onPressed: () {
                Navigator.pushNamed(context, '/savings_goal');
              },
              tooltip: 'View Savings Goal',
            ),
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: VoiceNavigationWidget(currentPage: 'wallet_scanner'),
           ),
        ],
      ),
      body: Column(
        children: [
          // Balance Display Area
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.blueGrey[800],
            child: Column(
              children: [
                Center(
                  child: Text(
                    "Balance: Rs. ${_currentBalance.toStringAsFixed(2)}",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Savings Goal Progress Bar
                if (_hasGoal && _activeGoal != null) ...[
                  SizedBox(height: 12),
                  _buildGoalProgressBar(),
                ],
              ],
            ),
          ),

          // Camera Preview Area
          Expanded(
            child: FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CameraPreview(_controller),
                      if (_isProcessing) CircularProgressIndicator(),
                    ],
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),

          // Status Message Area
          Container(
            color: Colors.black,
            padding: const EdgeInsets.all(20.0),
            child: Text(
              _statusMessage,
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isProcessing ? null : _scanAndProcessCurrency,
        tooltip: 'Scan Currency',
        child: _isProcessing
            ? CircularProgressIndicator(color: Colors.white)
            : Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildGoalProgressBar() {
    if (_activeGoal == null) return SizedBox.shrink();
    
    double goalAmount = _activeGoal!['goal_amount']?.toDouble() ?? 0.0;
    double currentSavings = _activeGoal!['current_savings']?.toDouble() ?? 0.0;
    double progress = _activeGoal!['progress_percentage']?.toDouble() ?? 0.0;
    double remaining = _activeGoal!['remaining']?.toDouble() ?? 0.0;
    
    bool isCompleted = currentSavings >= goalAmount;
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Goal: Rs. ${goalAmount.toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            Text(
              '${progress.toStringAsFixed(1)}%',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress / 100,
          minHeight: 8,
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation<Color>(
            isCompleted ? Colors.green : Colors.blue,
          ),
        ),
        SizedBox(height: 4),
        Text(
          isCompleted
              ? 'Goal Achieved! 🎉'
              : 'Rs. ${remaining.toStringAsFixed(2)} remaining',
          style: TextStyle(
            color: isCompleted ? Colors.greenAccent : Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
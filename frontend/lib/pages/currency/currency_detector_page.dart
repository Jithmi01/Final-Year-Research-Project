// lib/ar_currency_detector_page.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import '../../main.dart'; // Imports API_URL

class ARCurrencyDetectorPage extends StatefulWidget {
  final CameraDescription camera;
  const ARCurrencyDetectorPage({Key? key, required this.camera}) : super(key: key);

  @override
  _ARCurrencyDetectorPageState createState() => _ARCurrencyDetectorPageState();
}

class _ARCurrencyDetectorPageState extends State<ARCurrencyDetectorPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  FlutterTts flutterTts = FlutterTts();
  
  // AR Overlay State
  List<DetectedCurrency> _detectedCurrencies = [];
  bool _isScanning = false;
  Timer? _scanTimer;
  String _statusMessage = "Starting AR currency detector...";
  
  // Colors for different currency denominations
  final Map<int, Color> _currencyColors = {
    20: Colors.green,
    50: Colors.blue,
    100: Colors.orange,
    500: Colors.purple,
    1000: Colors.red,
    5000: Colors.pink,
  };

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera, 
      ResolutionPreset.high, 
      enableAudio: false
    );
    _initializeControllerFuture = _controller.initialize();
    _setupTts();
    _speak("AR Currency detector ready. Point camera at currency notes.");
    
    // Start continuous scanning after camera initializes
    _initializeControllerFuture.then((_) {
      _startContinuousScanning();
    });
  }

  void _setupTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await flutterTts.speak(text);
  }

  void _startContinuousScanning() {
    setState(() {
      _isScanning = true;
      _statusMessage = "Scanning for currency...";
    });
    
    // Scan every 2 seconds for better performance
    _scanTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (_isScanning) {
        _detectCurrencyWithAR();
      }
    });
  }

  void _stopScanning() {
    _scanTimer?.cancel();
    setState(() {
      _isScanning = false;
      _detectedCurrencies.clear();
      _statusMessage = "Scanning paused";
    });
  }

  Future<void> _detectCurrencyWithAR() async {
    if (!_controller.value.isInitialized || !mounted) return;

    try {
      final image = await _controller.takePicture();
      final File imageFile = File(image.path);

      // Call backend API
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse("$API_URL/detect_currency_ar")
      );
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        List<dynamic> detections = data['detections'] ?? [];
        
        if (mounted) {
          setState(() {
            _detectedCurrencies = detections
                .map((d) => DetectedCurrency.fromJson(d))
                .toList();
            
            if (_detectedCurrencies.isEmpty) {
              _statusMessage = "No currency detected. Keep scanning...";
            } else {
              _statusMessage = "${_detectedCurrencies.length} note(s) detected";
              _announceDetections();
            }
          });
        }
      }
    } catch (e) {
      print("Error during AR detection: $e");
    }
  }

  void _announceDetections() {
    if (_detectedCurrencies.isEmpty) return;

    // Sort currencies by horizontal position (left to right)
    var sorted = List<DetectedCurrency>.from(_detectedCurrencies);
    sorted.sort((a, b) => a.centerX.compareTo(b.centerX));

    String announcement = "";
    
    if (sorted.length == 1) {
      announcement = "Detected ${sorted[0].displayName} in center";
    } else {
      for (int i = 0; i < sorted.length; i++) {
        String position = _getPositionDescription(i, sorted.length);
        announcement += "${sorted[i].displayName} $position. ";
      }
    }

    _speak(announcement);
  }

  String _getPositionDescription(int index, int total) {
    if (total == 1) return "in center";
    if (total == 2) {
      return index == 0 ? "on your left" : "on your right";
    }
    if (total >= 3) {
      if (index == 0) return "on your left";
      if (index == total - 1) return "on your right";
      return "in the middle";
    }
    return "";
  }

  Color _getColorForAmount(int amount) {
    return _currencyColors[amount] ?? Colors.yellow;
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _controller.dispose();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AR Currency Detector'),
        backgroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
            onPressed: () {
              if (_isScanning) {
                _stopScanning();
              } else {
                _startContinuousScanning();
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                // Camera Preview
                Positioned.fill(
                  child: CameraPreview(_controller),
                ),
                
                // AR Overlays
                Positioned.fill(
                  child: CustomPaint(
                    painter: AROverlayPainter(
                      detectedCurrencies: _detectedCurrencies,
                      getColorForAmount: _getColorForAmount,
                    ),
                  ),
                ),
                
                // Status Bar at Top
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _isScanning ? Icons.radar : Icons.pause_circle,
                                  color: _isScanning ? Colors.green : Colors.orange,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _statusMessage,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            if (_isScanning)
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.greenAccent
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Currency Legend at Bottom
                if (_detectedCurrencies.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detected Notes:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          ..._detectedCurrencies.map((currency) => Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: _getColorForAmount(currency.amount),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  currency.displayName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  '${(currency.confidence * 100).toInt()}%',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'announce',
            onPressed: _detectedCurrencies.isEmpty ? null : _announceDetections,
            tooltip: 'Announce Detections',
            child: Icon(Icons.volume_up),
            backgroundColor: _detectedCurrencies.isEmpty 
                ? Colors.grey 
                : Colors.blue,
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'scan',
            onPressed: () {
              if (_isScanning) {
                _stopScanning();
              } else {
                _startContinuousScanning();
              }
            },
            tooltip: _isScanning ? 'Pause Scanning' : 'Start Scanning',
            child: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
            backgroundColor: _isScanning ? Colors.orange : Colors.green,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DETECTED CURRENCY MODEL
// ============================================================================
class DetectedCurrency {
  final int amount;
  final String label;
  final double confidence;
  final double x1, y1, x2, y2;
  final double centerX, centerY;

  DetectedCurrency({
    required this.amount,
    required this.label,
    required this.confidence,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.centerX,
    required this.centerY,
  });

  factory DetectedCurrency.fromJson(Map<String, dynamic> json) {
    return DetectedCurrency(
      amount: json['amount'],
      label: json['label'],
      confidence: json['confidence'].toDouble(),
      x1: json['x1'].toDouble(),
      y1: json['y1'].toDouble(),
      x2: json['x2'].toDouble(),
      y2: json['y2'].toDouble(),
      centerX: json['center_x'].toDouble(),
      centerY: json['center_y'].toDouble(),
    );
  }

  String get displayName => 'Rs. $amount';
}

// ============================================================================
// AR OVERLAY PAINTER
// ============================================================================
class AROverlayPainter extends CustomPainter {
  final List<DetectedCurrency> detectedCurrencies;
  final Color Function(int) getColorForAmount;

  AROverlayPainter({
    required this.detectedCurrencies,
    required this.getColorForAmount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var currency in detectedCurrencies) {
      final color = getColorForAmount(currency.amount);
      
      // Scale coordinates to screen size
      final x1 = currency.x1 * size.width;
      final y1 = currency.y1 * size.height;
      final x2 = currency.x2 * size.width;
      final y2 = currency.y2 * size.height;
      
      // Draw bounding box
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      
      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, paint);
      
      // Draw semi-transparent fill
      final fillPaint = Paint()
        ..color = color.withOpacity(0.2)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);
      
      // Draw label background
      final labelPainter = TextPainter(
        text: TextSpan(
          text: currency.displayName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                blurRadius: 4,
                color: Colors.black,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      labelPainter.layout();
      
      // Draw label at top of box
      final labelX = x1 + 8;
      final labelY = y1 - labelPainter.height - 8;
      
      // Background for label
      final labelBgPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            labelX - 4,
            labelY - 4,
            labelPainter.width + 8,
            labelPainter.height + 8,
          ),
          Radius.circular(4),
        ),
        labelBgPaint,
      );
      
      labelPainter.paint(canvas, Offset(labelX, labelY));
      
      // Draw confidence indicator
      final confidenceText = '${(currency.confidence * 100).toInt()}%';
      final confidencePainter = TextPainter(
        text: TextSpan(
          text: confidenceText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      confidencePainter.layout();
      confidencePainter.paint(
        canvas,
        Offset(x2 - confidencePainter.width - 8, y1 + 8),
      );
    }
  }

  @override
  bool shouldRepaint(AROverlayPainter oldDelegate) {
    return detectedCurrencies != oldDelegate.detectedCurrencies;
  }
}
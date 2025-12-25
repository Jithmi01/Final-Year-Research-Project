// lib/widgets/voice_navigation_widget.dart
import 'package:flutter/material.dart';
import '../services/voice_navigation_service.dart';
import '../main.dart';

// Import all pages
import '../screens/currency_bills/currency_bills_home.dart';
import '../pages/currency/ar_currency_detector_page.dart';
import '../pages/bills/bill_scanner_page.dart';
import '../pages/smart_wallet/wallet_scanner_page.dart';
import '../pages/smart_wallet/wallet_qa_page.dart';
import '../screens/face_detection/home_screen.dart';
import '../screens/face_detection/age_gender_screen.dart';
import '../screens/face_detection/face_recognition_screen.dart';
import '../screens/face_detection/attributes_screen.dart';

class VoiceNavigationWidget extends StatefulWidget {
  final String? currentPage; // To avoid navigating to same page
  
  const VoiceNavigationWidget({Key? key, this.currentPage}) : super(key: key);

  @override
  State<VoiceNavigationWidget> createState() => _VoiceNavigationWidgetState();
}

class _VoiceNavigationWidgetState extends State<VoiceNavigationWidget> {
  final VoiceNavigationService _voiceService = VoiceNavigationService();
  bool _isVoiceEnabled = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeVoiceService();
  }

  Future<void> _initializeVoiceService() async {
    bool initialized = await _voiceService.initialize();
    if (mounted) {
      setState(() {
        _isVoiceEnabled = initialized;
      });
    }
  }

  void _handleVoiceCommand() async {
    if (_isProcessing || _voiceService.isListening) {
      print('⚠️ Already processing or listening');
      return;
    }

    if (!_isVoiceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice navigation not available')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _voiceService.startListening(
        onResult: (command) async {
          print('📢 Command received: $command');
          
          String? route = _voiceService.parseNavigationCommand(command);
          
          if (route != null) {
            // Check if trying to navigate to current page
            if (route == widget.currentPage) {
              await _voiceService.speak("You are already on this page");
              if (mounted) {
                setState(() {
                  _isProcessing = false;
                });
              }
              return;
            }

            String routeName = _voiceService.getRouteName(route);
            await _voiceService.speak("Navigating to $routeName");
            
            await Future.delayed(Duration(milliseconds: 800));
            
            if (mounted) {
              _navigateToRoute(route);
            }
          } else {
            await _voiceService.speak("Command not recognized");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Command not recognized: $command')),
              );
            }
          }
          
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        },
        onError: (error) async {
          print('❌ Voice error: $error');
          await _voiceService.speak("Voice error occurred");
          
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        },
      );

      // Timeout safety
      Future.delayed(Duration(seconds: 10), () {
        if (mounted && _isProcessing) {
          setState(() => _isProcessing = false);
        }
      });

    } catch (e) {
      print('❌ Exception: $e');
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
      case 'home':
        // Pop to root (main page)
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
        
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
    }

    if (page != null && mounted) {
      // If on a sub-page, replace current page. If on main page, push
      if (widget.currentPage != null && widget.currentPage != 'home') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => page!),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => page!),
        );
      }
    } else if (page == null && cameras.isEmpty) {
      _voiceService.speak("Camera not available");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      heroTag: 'voice_nav_${widget.currentPage}',
      onPressed: (_isVoiceEnabled && !_isProcessing) ? _handleVoiceCommand : null,
      backgroundColor: _voiceService.isListening 
          ? Colors.red 
          : (_isProcessing ? Colors.grey : Colors.blue),
      child: Icon(
        _voiceService.isListening ? Icons.mic : Icons.mic_none,
        color: Colors.white,
      ),
      tooltip: _voiceService.isListening ? 'Listening...' : 'Voice Navigation',
    );
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}
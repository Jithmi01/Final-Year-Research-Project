// lib/services/voice_navigation_service.dart
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceNavigationService {
  stt.SpeechToText? _speech;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  bool _isInitialized = false;
  bool _isSpeaking = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  // Initialize TTS and Speech Recognition
  Future<bool> initialize() async {
    try {
      // Request microphone permission
      var status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('❌ Microphone permission denied');
        return false;
      }

      // Initialize TTS
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      // Set TTS completion handler
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        print('✅ TTS completed');
      });

      // Create new speech instance
      _speech = stt.SpeechToText();
      
      // Initialize Speech Recognition
      _isInitialized = await _speech!.initialize(
        onStatus: (status) {
          print('🎤 Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            print('🔄 Speech stopped, ready for next command');
          }
        },
        onError: (error) {
          print('❌ Speech error: ${error.errorMsg}');
          _isListening = false;
        },
      );

      if (_isInitialized) {
        print('✅ Voice navigation initialized successfully');
      } else {
        print('❌ Failed to initialize speech recognition');
      }

      return _isInitialized;
    } catch (e) {
      print('❌ Error initializing voice service: $e');
      return false;
    }
  }

  // Reinitialize speech recognition for next use
  Future<void> _reinitializeSpeech() async {
    try {
      print('🔄 Reinitializing speech recognition...');
      
      // Stop and dispose old instance
      if (_speech != null) {
        await _speech!.stop();
        _speech = null;
      }
      
      // Small delay
      await Future.delayed(Duration(milliseconds: 300));
      
      // Create fresh instance
      _speech = stt.SpeechToText();
      
      _isInitialized = await _speech!.initialize(
        onStatus: (status) {
          print('🎤 Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
          }
        },
        onError: (error) {
          print('❌ Speech error: ${error.errorMsg}');
          _isListening = false;
        },
      );
      
      print('✅ Speech reinitialized: $_isInitialized');
    } catch (e) {
      print('❌ Error reinitializing speech: $e');
      _isInitialized = false;
    }
  }

  // Speak text
  Future<void> speak(String text) async {
    try {
      if (_isSpeaking) {
        await _flutterTts.stop();
      }
      _isSpeaking = true;
      print('🔊 Speaking: $text');
      await _flutterTts.speak(text);
      
      // Wait for speech to complete
      await Future.delayed(Duration(milliseconds: 1500));
      _isSpeaking = false;
    } catch (e) {
      print('❌ TTS error: $e');
      _isSpeaking = false;
    }
  }

  // Start listening for voice commands
  Future<void> startListening({
    required Function(String) onResult,
    required Function(String) onError,
  }) async {
    // Check if already listening
    if (_isListening) {
      print('⚠️ Already listening, ignoring request');
      return;
    }

    try {
      // Ensure speech is initialized
      if (_speech == null || !_isInitialized) {
        print('🔄 Speech not initialized, initializing now...');
        bool initialized = await initialize();
        if (!initialized) {
          onError('Voice recognition not available');
          return;
        }
      }

      // Stop any ongoing speech session
      if (_speech!.isListening) {
        print('🛑 Stopping previous listening session');
        await _speech!.stop();
        await Future.delayed(Duration(milliseconds: 500));
      }

      _isListening = true;
      print('🎤 Starting to listen...');
      
      await speak("Listening for command");

      // Start listening
      bool started = await _speech!.listen(
        onResult: (result) {
          print('📝 Result - Final: ${result.finalResult}, Words: "${result.recognizedWords}"');
          
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            String command = result.recognizedWords.toLowerCase().trim();
            print('✅ Final command: "$command"');
            
            // Stop listening
            _speech!.stop();
            _isListening = false;
            
            // Process command
            onResult(command);
            
            // Reinitialize for next use
            Future.delayed(Duration(milliseconds: 500), () {
              _reinitializeSpeech();
            });
          }
        },
        listenFor: Duration(seconds: 6),
        pauseFor: Duration(seconds: 3),
        partialResults: true,
        onSoundLevelChange: (level) {
          // Optional: visual feedback
        },
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );

      if (!started) {
        print('❌ Failed to start listening');
        _isListening = false;
        onError('Failed to start listening');
        
        // Try to reinitialize
        await _reinitializeSpeech();
      } else {
        print('✅ Listening started successfully');
      }

    } catch (e) {
      print('❌ Error starting listener: $e');
      _isListening = false;
      onError('Failed to start listening: $e');
      
      // Try to reinitialize
      await _reinitializeSpeech();
    }
  }

  // Stop listening
  Future<void> stopListening() async {
    if (_isListening && _speech != null) {
      print('🛑 Manually stopping listening');
      await _speech!.stop();
      _isListening = false;
      
      // Reinitialize for next use
      await Future.delayed(Duration(milliseconds: 300));
      await _reinitializeSpeech();
    }
  }

  // Parse voice command and return navigation route
  String? parseNavigationCommand(String command) {
    command = command.toLowerCase().trim();
    
    print('🔍 Parsing command: "$command"');

    // Home/back commands - Check first for priority
    if (_containsAny(command, ['home', 'main menu', 'go back'])) {
      print('✅ Matched: home');
      return 'home';
    }

    // Currency & Bills main page
    if (_containsAny(command, ['currency bills', 'currency and bills', 'currency home'])) {
      print('✅ Matched: currency_home');
      return 'currency_home';
    }

    // AR Currency Detector (most specific first)
    if (_containsAny(command, ['ar currency', 'ar detector', 'currency detector', 'detect currency'])) {
      print('✅ Matched: ar_currency');
      return 'ar_currency';
    }

    // Bill Scanner
    if (_containsAny(command, ['bill', 'bill scanner', 'scan bill', 'receipt', 'invoice'])) {
      print('✅ Matched: bill_scanner');
      return 'bill_scanner';
    }

    // Wallet Q&A (check before wallet scanner)
    if (_containsAny(command, ['wallet question', 'wallet qa', 'wallet q&a', 'ask wallet', 'wallet query'])) {
      print('✅ Matched: wallet_qa');
      return 'wallet_qa';
    }

    // Wallet Scanner
    if (_containsAny(command, ['wallet', 'wallet scanner', 'scan wallet', 'add money', 'add cash'])) {
      print('✅ Matched: wallet_scanner');
      return 'wallet_scanner';
    }

    // Currency (general - after specific checks)
    if (_containsAny(command, ['currency', 'money', 'cash'])) {
      print('✅ Matched: currency_home');
      return 'currency_home';
    }

    // Face Detection main page
    if (_containsAny(command, ['face home', 'face detection home', 'blind assistant'])) {
      print('✅ Matched: face_home');
      return 'face_home';
    }

    // Age & Gender (most specific first)
    if (_containsAny(command, ['age gender', 'age and gender', 'detect age', 'gender detection'])) {
      print('✅ Matched: age_gender');
      return 'age_gender';
    }

    // Face Recognition
    if (_containsAny(command, ['face recognition', 'recognize face', 'identify person', 'who is this'])) {
      print('✅ Matched: face_recognition');
      return 'face_recognition';
    }

    // Attributes
    if (_containsAny(command, ['attribute', 'attributes', 'facial attribute', 'face feature', 'glasses', 'hat'])) {
      print('✅ Matched: attributes');
      return 'attributes';
    }

    // Face (general - after specific checks)
    if (_containsAny(command, ['face', 'facial'])) {
      print('✅ Matched: face_home');
      return 'face_home';
    }

    print('❌ No match found for command');
    return null;
  }

  // Helper method to check if command contains any keywords
  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }

  // Get friendly name for route
  String getRouteName(String route) {
    switch (route) {
      case 'home':
        return 'Home';
      case 'currency_home':
        return 'Currency and Bills';
      case 'ar_currency':
        return 'AR Currency Detector';
      case 'bill_scanner':
        return 'Bill Scanner';
      case 'wallet_scanner':
        return 'Wallet Scanner';
      case 'wallet_qa':
        return 'Wallet Q&A';
      case 'face_home':
        return 'Face Detection';
      case 'age_gender':
        return 'Age and Gender Detection';
      case 'face_recognition':
        return 'Face Recognition';
      case 'attributes':
        return 'Facial Attributes';
      default:
        return 'Unknown';
    }
  }

  // Check if microphone permission is granted
  Future<bool> checkMicrophonePermission() async {
    var status = await Permission.microphone.status;
    return status.isGranted;
  }

  // Request microphone permission
  Future<bool> requestMicrophonePermission() async {
    var status = await Permission.microphone.request();
    return status.isGranted;
  }

  // Cleanup
  Future<void> dispose() async {
    if (_speech != null) {
      await _speech!.stop();
      _speech = null;
    }
    await _flutterTts.stop();
    _isListening = false;
    _isSpeaking = false;
    _isInitialized = false;
  }
}
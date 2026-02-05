// lib/pages/document/document_reader_page.dart
// DOCUMENT READER - Continuous Reading + Capture Mode + Voice Q&A

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'dart:io';
import '../../services/document_service.dart';
import '../../models/document_model.dart';

class DocumentReaderPage extends StatefulWidget {
  final CameraDescription camera;

  const DocumentReaderPage({Key? key, required this.camera}) : super(key: key);

  @override
  _DocumentReaderPageState createState() => _DocumentReaderPageState();
}

class _DocumentReaderPageState extends State<DocumentReaderPage> {
  // Camera
  late CameraController _cameraController;
  bool _isCameraInitialized = false;

  // Services
  final DocumentService _documentService = DocumentService();
  final FlutterTts _tts = FlutterTts();
  late stt.SpeechToText _speech;

  // Reading modes
  ReadingMode _currentMode = ReadingMode.continuous;
  bool _isReading = false;
  Timer? _readingTimer;

  // Captured document
  DocumentData? _capturedDocument;
  bool _hasDocument = false;

  // Voice Q&A
  bool _isListeningForQuestion = false;
  String _currentQuestion = '';

  // UI State
  String _statusMessage = 'Point camera at document to start reading';
  bool _isSpeaking = false;
  List<String> _recentlyReadText = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeTTS();
    _initializeSpeech();
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    _cameraController.dispose();
    _tts.stop();
    super.dispose();
  }

  // ========================================================================
  // INITIALIZATION
  // ========================================================================

  Future<void> _initializeCamera() async {
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print('Camera initialization error: $e');
      _showError('Camera initialization failed');
    }
  }

  Future<void> _initializeTTS() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });

    _tts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  Future<void> _initializeSpeech() async {
    _speech = stt.SpeechToText();
    bool available = await _speech.initialize(
      onStatus: (status) => print('Speech status: $status'),
      onError: (error) => print('Speech error: $error'),
    );

    if (!available) {
      print('Speech recognition not available');
    }
  }

  // ========================================================================
  // READING MODES
  // ========================================================================

  void _startContinuousReading() {
    if (_isReading) return;

    setState(() {
      _isReading = true;
      _currentMode = ReadingMode.continuous;
      _statusMessage = 'Reading continuously... Move camera to read text';
    });

    _speak('Continuous reading mode activated');

    // Read every 2 seconds
    _readingTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      _captureAndReadContinuous();
    });
  }

  void _stopContinuousReading() {
    setState(() {
      _isReading = false;
      _statusMessage = 'Continuous reading stopped';
    });

    _readingTimer?.cancel();
    _speak('Reading stopped');
  }

  Future<void> _captureAndReadContinuous() async {
    if (!_isCameraInitialized || _isSpeaking) return;

    try {
      final image = await _cameraController.takePicture();
      final result = await _documentService.readContinuous(File(image.path));

      if (result.success && result.shouldSpeak && result.voicePrompt.isNotEmpty) {
        // New text detected
        setState(() {
          _recentlyReadText.insert(0, result.voicePrompt);
          if (_recentlyReadText.length > 5) {
            _recentlyReadText.removeLast();
          }
        });

        await _speak(result.voicePrompt);
      }
    } catch (e) {
      print('Continuous read error: $e');
    }
  }

  // ========================================================================
  // CAPTURE MODE
  // ========================================================================

  Future<void> _captureDocument() async {
    if (!_isCameraInitialized) return;

    setState(() {
      _statusMessage = 'Capturing document...';
    });

    try {
      // Stop continuous reading if active
      if (_isReading) {
        _stopContinuousReading();
      }

      final image = await _cameraController.takePicture();
      final result = await _documentService.captureDocument(File(image.path));

      if (result.success) {
        setState(() {
          _capturedDocument = result;
          _hasDocument = true;
          _currentMode = ReadingMode.captured;
          _statusMessage = 'Document captured. Ask questions or read lines.';
        });

        await _speak(result.voicePrompt);

        // Show document details dialog
        _showDocumentDetailsDialog();
      } else {
        _showError(result.error ?? 'Failed to capture document');
      }
    } catch (e) {
      print('Capture error: $e');
      _showError('Capture failed: $e');
    }
  }

  // ========================================================================
  // VOICE Q&A
  // ========================================================================

  Future<void> _startVoiceQuestion() async {
    if (!_hasDocument) {
      _speak('Please capture a document first before asking questions');
      return;
    }

    if (!_speech.isAvailable) {
      _speak('Speech recognition not available');
      return;
    }

    setState(() {
      _isListeningForQuestion = true;
      _statusMessage = 'Listening for your question...';
    });

    await _speak('Ask your question now');

    await _speech.listen(
      onResult: (result) async {
        if (result.finalResult) {
          String question = result.recognizedWords;

          setState(() {
            _currentQuestion = question;
            _isListeningForQuestion = false;
            _statusMessage = 'Answering: "$question"';
          });

          print('Question: $question');

          // Send question to backend
          final answer = await _documentService.askQuestion(question);

          if (answer.success) {
            await _speak(answer.voicePrompt);

            // Show answer dialog
            _showAnswerDialog(question, answer);
          } else {
            _speak(answer.voicePrompt);
          }
        }
      },
      listenFor: Duration(seconds: 10),
      pauseFor: Duration(seconds: 3),
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListeningForQuestion = false;
      _statusMessage = 'Question cancelled';
    });
  }

  // ========================================================================
  // QUICK QUESTIONS (Pre-defined)
  // ========================================================================

  Future<void> _askQuickQuestion(String question) async {
    if (!_hasDocument) {
      _speak('Please capture a document first');
      return;
    }

    setState(() {
      _statusMessage = 'Asking: "$question"';
    });

    final answer = await _documentService.askQuestion(question);

    if (answer.success) {
      await _speak(answer.voicePrompt);
      _showAnswerDialog(question, answer);
    } else {
      _speak(answer.voicePrompt);
    }
  }

  // ========================================================================
  // TTS & DIALOGS
  // ========================================================================

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await _tts.speak(text);
  }

  void _showDocumentDetailsDialog() {
    if (_capturedDocument == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('📄 Document Captured'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lines: ${_capturedDocument!.lineCount}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              if (_capturedDocument!.metadata.dates.isNotEmpty) ...[
                Text('📅 Date: ${_capturedDocument!.metadata.dates.first}'),
                SizedBox(height: 8),
              ],
              if (_capturedDocument!.metadata.amounts.isNotEmpty) ...[
                Text('💰 Amounts: ${_capturedDocument!.metadata.amounts.join(", ")}'),
                SizedBox(height: 8),
              ],
              if (_capturedDocument!.metadata.phones.isNotEmpty) ...[
                Text('📞 Phone: ${_capturedDocument!.metadata.phones.first}'),
                SizedBox(height: 8),
              ],
              Divider(),
              Text(
                'Full Text:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _capturedDocument!.text,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _speak(_capturedDocument!.text);
            },
            child: Text('🔊 Read Aloud'),
          ),
        ],
      ),
    );
  }

  void _showAnswerDialog(String question, QuestionAnswer answer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('💬 Q&A'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Question:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            Text(question, style: TextStyle(fontSize: 14)),
            SizedBox(height: 12),
            Text(
              'Answer:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            Text(answer.answer, style: TextStyle(fontSize: 16)),
            if (answer.foundInLine != null) ...[
              SizedBox(height: 8),
              Text(
                'Found in line ${answer.foundInLine! + 1}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              _speak(answer.answer);
            },
            child: Text('🔊 Repeat'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
    _speak(message);
  }

  // ========================================================================
  // UI BUILD
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📄 Document Reader'),
        actions: [
          // Mode indicator
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                _currentMode == ReadingMode.continuous ? '📖 LIVE' : '📷 CAPTURED',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isReading ? Colors.green : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            flex: 3,
            child: _isCameraInitialized
                ? Stack(
                    children: [
                      CameraPreview(_cameraController),
                      // Status overlay
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusMessage,
                            style: TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      // Speaking indicator
                      if (_isSpeaking)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.volume_up, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Speaking...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Listening indicator
                      if (_isListeningForQuestion)
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.mic, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Listening...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(child: CircularProgressIndicator()),
          ),

          // Recently read text (for continuous mode)
          if (_currentMode == ReadingMode.continuous && _recentlyReadText.isNotEmpty)
            Container(
              padding: EdgeInsets.all(12),
              color: Colors.grey[900],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recently Read:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                  SizedBox(height: 8),
                  ..._recentlyReadText.take(3).map((text) => Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $text',
                          style: TextStyle(fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                ],
              ),
            ),

          // Controls
          Expanded(
            flex: 2,
            child: Container(
              padding: EdgeInsets.all(16),
              color: Colors.grey[900],
              child: _currentMode == ReadingMode.continuous
                  ? _buildContinuousModeControls()
                  : _buildCapturedModeControls(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinuousModeControls() {
    return Column(
      children: [
        Text(
          '📖 CONTINUOUS READING MODE',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        SizedBox(height: 16),
        // Start/Stop reading
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isReading ? _stopContinuousReading : _startContinuousReading,
                icon: Icon(_isReading ? Icons.stop : Icons.play_arrow),
                label: Text(_isReading ? 'Stop Reading' : 'Start Reading'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isReading ? Colors.red : Colors.green,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        // Switch to capture mode
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentMode = ReadingMode.captured;
                    if (_isReading) _stopContinuousReading();
                  });
                },
                icon: Icon(Icons.camera_alt),
                label: Text('Switch to Capture Mode'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCapturedModeControls() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Text(
            '📷 CAPTURE MODE',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 16),

          // Capture button
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _captureDocument,
                  icon: Icon(Icons.camera),
                  label: Text('Capture Document'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),

          if (_hasDocument) ...[
            SizedBox(height: 16),
            Text(
              'Ask Questions:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 8),

            // Voice question button
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isListeningForQuestion ? _stopListening : _startVoiceQuestion,
                    icon: Icon(_isListeningForQuestion ? Icons.mic_off : Icons.mic),
                    label: Text(_isListeningForQuestion ? 'Cancel' : 'Ask via Voice'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isListeningForQuestion ? Colors.red : Colors.orange,
                      padding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 12),
            Text(
              'Quick Questions:',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
            SizedBox(height: 8),

            // Quick question buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickQuestionButton('What is the total?'),
                _buildQuickQuestionButton('What is the date?'),
                _buildQuickQuestionButton('Who is the sender?'),
                _buildQuickQuestionButton('Read all'),
              ],
            ),
          ],

          SizedBox(height: 16),

          // Switch to continuous mode
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _currentMode = ReadingMode.continuous;
                    });
                  },
                  icon: Icon(Icons.auto_stories),
                  label: Text('Switch to Continuous Reading'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQuestionButton(String question) {
    return ElevatedButton(
      onPressed: () => _askQuickQuestion(question),
      child: Text(question, style: TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[800],
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

enum ReadingMode {
  continuous,
  captured,
}
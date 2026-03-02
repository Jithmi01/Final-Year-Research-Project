// lib/screens/face_detection/voice_identification_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../../services/audio_service.dart';

class VoiceIdentificationScreen extends StatefulWidget {
  const VoiceIdentificationScreen({Key? key}) : super(key: key);

  @override
  State<VoiceIdentificationScreen> createState() => _VoiceIdentificationScreenState();
}

class _VoiceIdentificationScreenState extends State<VoiceIdentificationScreen>
    with SingleTickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  final FlutterTts _tts = FlutterTts();

  bool _isRecording = false;
  bool _isIdentifying = false;
  int _recordingCountdown = 0;
  final int _recordDuration = 5;

  Map<String, dynamic>? _identificationResult;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _speak("identification start.");

    // Auto-start voice identification after TTS message
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      _startIdentification();
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioService.dispose();
    _tts.stop();
    super.dispose();
  }

  // ── NEW: Parse ISO-8601 UTC string and format it for speech / display ──────

  /// Converts an ISO-8601 UTC string (e.g. "2026-01-10T11:00:00.000Z")
  /// to a human-readable string like "2026/01/10 11:00 AM".
  String _formatLastSeen(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final year  = dt.year.toString();
      final month = dt.month.toString().padLeft(2, '0');
      final day   = dt.day.toString().padLeft(2, '0');

      final hour24 = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour24 >= 12 ? 'PM' : 'AM';
      final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;

      return "$year/$month/$day $hour12:$minute $period";
    } catch (_) {
      return isoString; // fallback: return raw string
    }
  }

  // ── NEW: Build TTS phrase and announce previous last-seen time ─────────────
  Future<void> _announceLastSeen(String name, String? lastSeenIso) async {
    if (lastSeenIso == null || lastSeenIso.isEmpty) {
      // First-time meeting – no previous record
      await _speak("$name identified.");
    } else {
      final formatted = _formatLastSeen(lastSeenIso);
      await _speak("$name identified. Met on $formatted.");
    }
  }
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _startIdentification() async {
    if (!await _audioService.hasPermission()) {
      final granted = await _audioService.requestPermission();
      if (!granted) {
        _showMessage('Microphone permission is required', isError: true);
        return;
      }
    }

    setState(() {
      _isRecording = true;
      _recordingCountdown = _recordDuration;
      _identificationResult = null;
    });

    await _speak("Analysing start");
    await Future.delayed(const Duration(milliseconds: 500));

    final started = await _audioService.startRecording();

    if (!started) {
      setState(() => _isRecording = false);
      _showMessage('Failed to start recording', isError: true);
      return;
    }

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_recordingCountdown > 0) {
        setState(() => _recordingCountdown--);
      } else {
        timer.cancel();
      }
    });

    await Future.delayed(Duration(seconds: _recordDuration));

    if (!mounted) return;

    final path = await _audioService.stopRecording();

    setState(() {
      _isRecording = false;
      _isIdentifying = true;
    });

    await _speak("Analyzing voice. Please wait.");

    if (path != null) {
      try {
        final result = await ApiService.identifyVoiceSpeaker(audioFilePath: path);

        setState(() => _isIdentifying = false);

        if (result['success'] == true) {
          final identResult = result['result'];
          setState(() => _identificationResult = identResult);

          final name      = identResult['name'] ?? 'Unknown';
          final lastSeen  = identResult['last_seen'] as String?;

          await _announceLastSeen(name, lastSeen);

          // ── NEW: Auto-restart detection after 5 seconds ──
          await Future.delayed(const Duration(seconds: 10));
          if (mounted) {
            _startIdentification();
          }
          // ───────────────────────────────────────────────
        } else {
          _showMessage(result['error'] ?? 'Identification failed', isError: true);
          await _speak("Identification failed");
        }

        await _audioService.deleteAudioFile(path);
      } catch (e) {
        setState(() => _isIdentifying = false);
        _showMessage('Error: $e', isError: true);
        await _speak("Error occurred");
      }
    } else {
      setState(() => _isIdentifying = false);
      _showMessage('Failed to save recording', isError: true);
      await _speak("Recording failed");
    }
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 80) return Colors.green;
    if (confidence >= 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Voice Identification', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.search_rounded, size: 64, color: Colors.blue),
              const SizedBox(height: 16),

              const Text(
                'Speaker Identification',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              if (_isRecording)
                _buildRecordingCard()
              else if (_isIdentifying)
                _buildIdentifyingCard()
              else if (_identificationResult != null)
                _buildResultCard()
              else
                _buildReadyCard(),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _startIdentification,
                icon: const Icon(Icons.mic, size: 24),
                label: Text(
                  _identificationResult != null ? 'Identify Again' : 'Start Identification',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),

              const SizedBox(height: 20),

              _buildInstructions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadyCard() {
    return Card(
      color: const Color(0xFF2C2C2C),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_none_rounded, size: 60, color: Colors.blue),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ready to Identify',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to start',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingCard() {
    return Card(
      color: Colors.red.shade900.withOpacity(0.3),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.2),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1 + (_pulseController.value * 0.2)),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.fiber_manual_record,
                      size: 60,
                      color: Colors.red.withOpacity(0.7 + (_pulseController.value * 0.3)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Recording...',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 12),
            Text(
              '$_recordingCountdown',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'seconds remaining',
              style: TextStyle(fontSize: 16, color: Colors.red.shade400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentifyingCard() {
    return Card(
      color: const Color(0xFF2C2C2C),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(strokeWidth: 6, color: Colors.blue),
            ),
            const SizedBox(height: 20),
            const Text(
              'Identifying Speaker...',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            const SizedBox(height: 12),
            Text(
              'Analyzing voice patterns',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final result      = _identificationResult!;
    final isIdentified = result['identified'] ?? false;
    final name        = result['name'] ?? 'Unknown';
    final confidence  = (result['confidence'] ?? 0.0).toDouble();
    // ── NEW: pull last_seen from result ──
    final lastSeenIso = result['last_seen'] as String?;
    final lastSeenDisplay = (lastSeenIso != null && lastSeenIso.isNotEmpty)
        ? _formatLastSeen(lastSeenIso)
        : null;

    Color cardColor;
    Color iconColor;
    IconData iconData;
    String statusText;

    if (name == "Can't hear someone speaking") {
      cardColor  = Colors.grey.shade800;
      iconColor  = Colors.grey;
      iconData   = Icons.volume_off;
      statusText = 'No Voice Detected';
    } else if (name == "Unknown Person Speaking") {
      cardColor  = Colors.orange.shade900.withOpacity(0.3);
      iconColor  = Colors.orange;
      iconData   = Icons.help_outline;
      statusText = 'Unknown Speaker';
    } else if (isIdentified && confidence >= 30) {
      if (confidence >= 70) {
        cardColor  = Colors.green.shade900.withOpacity(0.3);
        iconColor  = Colors.green;
        iconData   = Icons.check_circle;
        statusText = 'Speaker Identified!';
      } else {
        cardColor  = Colors.blue.shade900.withOpacity(0.3);
        iconColor  = Colors.blue;
        iconData   = Icons.person_search;
        statusText = 'Possible Match';
      }
    } else {
      cardColor  = Colors.grey.shade800;
      iconColor  = Colors.grey;
      iconData   = Icons.help_outline;
      statusText = 'No Match';
    }

    final confidenceColor = _getConfidenceColor(confidence);

    return Card(
      color: cardColor,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, size: 60, color: iconColor),
            ),
            const SizedBox(height: 16),

            Text(
              statusText,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 12),

            if (name != "Can't hear someone speaking")
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: iconColor.withOpacity(0.3), width: 2),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: name == "Unknown Person Speaking" ? 18 : 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 20),

            // ── NEW: Last seen badge ──────────────────────────────────────
            if (name != "Can't hear someone speaking" &&
                name != "Unknown Person Speaking" &&
                isIdentified)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.purple.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Colors.purpleAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Last Met',
                            style: TextStyle(
                              color: Colors.purpleAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastSeenDisplay ?? 'First meeting',
                            style: TextStyle(
                              color: lastSeenDisplay != null
                                  ? Colors.white
                                  : Colors.grey[400],
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // ────────────────────────────────────────────────────────────

            if (name != "Can't hear someone speaking")
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                ),
                // child: Column(
                //   children: [
                //     Row(
                //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                //       children: [
                //         const Text(
                //           'Confidence',
                //           style: TextStyle(
                //             fontWeight: FontWeight.bold,
                //             fontSize: 16,
                //             color: Colors.white,
                //           ),
                //         ),
                //         Text(
                //           '${confidence.toStringAsFixed(1)}%',
                //           style: TextStyle(
                //             fontWeight: FontWeight.bold,
                //             fontSize: 20,
                //             color: confidenceColor,
                //           ),
                //         ),
                //       ],
                //     ),
                //     const SizedBox(height: 12),
                //     ClipRRect(
                //       borderRadius: BorderRadius.circular(8),
                //       child: LinearProgressIndicator(
                //         value: confidence / 100,
                //         minHeight: 12,
                //         backgroundColor: Colors.grey[700],
                //         valueColor: AlwaysStoppedAnimation<Color>(confidenceColor),
                //       ),
                //     ),
                //   ],
                // ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Card(
      color: const Color(0xFF2C2C2C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'How to Use',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInstruction('1. Live Identification starts automatically'),
            _buildInstruction('2. Speak clearly for $_recordDuration seconds'),
            _buildInstruction('3. Wait for AI analysis'),
            _buildInstruction('4. View identified speaker & last meeting time'),
          ],
        ),
      ),
    );
  }

  Widget _buildInstruction(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16, color: Colors.white)),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.grey[400])),
          ),
        ],
      ),
    );
  }
}
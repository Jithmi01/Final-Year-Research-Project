// lib/screens/face_detection/voice_identification_screen.dart
//
// ══════════════════════════════════════════════════════════════════════════════
// FLOW:
//  [A] Screen opens → TTS greeting → 600ms silence gap → mic starts
//  [B] User taps → mic STOPS FIRST → then TTS speaks "Analysing"
//      (mic is never open while TTS is playing)
//  [C] Result card shown (name + last met) + TTS announces
//  [D] TTS finishes → 600ms gap → mic restarts from [A]
//  Runs forever until user presses back.
//
// KEY FIXES vs previous version:
//  • Mic is always stopped BEFORE TTS speaks — no echo contamination
//  • 600 ms silence gap after every TTS before mic opens
//  • Minimum 2 s recording guard — short taps are ignored
//  • "Analysing" TTS only plays AFTER stopRecording() returns
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../services/api_service.dart';
import '../../services/audio_service.dart';

enum _Phase { initialising, listening, processing, showingResult, error }

class VoiceIdentificationScreen extends StatefulWidget {
  const VoiceIdentificationScreen({Key? key}) : super(key: key);

  @override
  State<VoiceIdentificationScreen> createState() =>
      _VoiceIdentificationScreenState();
}

class _VoiceIdentificationScreenState extends State<VoiceIdentificationScreen>
    with TickerProviderStateMixin {

  final AudioService _audioService = AudioService();
  final FlutterTts   _tts          = FlutterTts();

  _Phase _phase = _Phase.initialising;
  Map<String, dynamic>? _lastResult;

  // Track when recording started so we can enforce minimum duration
  DateTime? _recordingStartTime;
  static const int _minRecordingMs = 2000; // at least 2 seconds of audio

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late List<AnimationController> _barControllers;
  static const int _barCount = 20;

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _barControllers = List.generate(_barCount, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 600 + (i % 5) * 80),
      );
      Future.delayed(Duration(milliseconds: i * 30), () {
        if (mounted) ctrl.repeat(reverse: true);
      });
      return ctrl;
    });

    _bootstrap();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    for (final c in _barControllers) { c.dispose(); }
    _audioService.dispose();
    _tts.stop();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOOTSTRAP
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _bootstrap() async {
    _setPhase(_Phase.initialising);

    // awaitSpeakCompletion(true) → tts.speak() blocks until audio finishes
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);

    if (!await _audioService.hasPermission()) {
      final ok = await _audioService.requestPermission();
      if (!ok) { _setPhase(_Phase.error); return; }
    }

    // Speak greeting — mic is NOT open yet
    await _tts.speak('Ready. Tap screen to identify speaker.');

    // ── GAP: wait for speaker echo to die before opening mic ──
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) _startListening();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // START LISTENING  (mic opens here — TTS must be silent before this call)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startListening() async {
    if (!mounted) return;

    setState(() => _lastResult = null);

    final ok = await _audioService.startRecording();
    if (!ok) { _setPhase(_Phase.error); return; }

    _recordingStartTime = DateTime.now();
    _setPhase(_Phase.listening);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAP HANDLER
  // ══════════════════════════════════════════════════════════════════════════

  void _onTap() {
    if (_phase != _Phase.listening) return;

    // Enforce minimum recording duration — ignore accidental quick taps
    if (_recordingStartTime != null) {
      final elapsed = DateTime.now()
          .difference(_recordingStartTime!)
          .inMilliseconds;
      if (elapsed < _minRecordingMs) return; // too short, ignore tap
    }

    _stopAndIdentify();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STOP & IDENTIFY
  // Order: stopRecording → speak "Analysing" → send to API
  // Mic is CLOSED before any TTS plays.
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _stopAndIdentify() async {
    _setPhase(_Phase.processing);

    // ── 1. Stop mic FIRST — before any TTS ──
    final path = await _audioService.stopRecording();

    if (path == null) {
      // Speak error only after mic is confirmed stopped
      await _tts.speak('Recording failed.');
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _startListening();
      return;
    }

    // ── 2. Now safe to speak — mic is closed ──
    await _tts.speak('Analysing.');

    // ── 3. Send audio to backend ──
    try {
      final resp = await ApiService.identifyVoiceSpeaker(audioFilePath: path);
      await _audioService.deleteAudioFile(path);
      if (!mounted) return;

      if (resp['success'] == true) {
        final result = resp['result'] as Map<String, dynamic>;
        setState(() => _lastResult = result);
        _setPhase(_Phase.showingResult);

        // Announce result — mic is still closed, safe to speak
        await _announceResult(result);
      } else {
        await _tts.speak('Identification failed. Please try again.');
      }
    } catch (e) {
      await _audioService.deleteAudioFile(path);
      await _tts.speak('Connection error. Please try again.');
    }

    // ── 4. Gap after TTS before reopening mic ──
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) _startListening();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANNOUNCE RESULT  (mic is closed here — safe to speak)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _announceResult(Map<String, dynamic> result) async {
    final name       = result['name'] as String? ?? '';
    final identified = result['identified'] as bool? ?? false;
    final lastSeen   = result['last_seen'] as String?;

    final isKnown = identified &&
        name.isNotEmpty &&
        name != 'No users registered'         &&
        name != 'Unknown Person Speaking'     &&
        name != "Can't hear someone speaking" &&
        name != 'Error';

    String announcement;
    if (name == "Can't hear someone speaking" || name.isEmpty) {
      announcement = 'No voice detected.';
    } else if (!isKnown) {
      announcement = 'Unknown person detected.';
    } else {
      announcement = (lastSeen != null && lastSeen.isNotEmpty)
          ? '$name identified. Last met on ${_fmt(lastSeen)}.'
          : '$name identified.';
    }

    await _tts.speak(announcement);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  void _setPhase(_Phase p) { if (mounted) setState(() => _phase = p); }

  String _fmt(String iso) {
    try {
      final dt  = DateTime.parse(iso).toLocal();
      final m   = dt.month.toString().padLeft(2, '0');
      final d   = dt.day.toString().padLeft(2, '0');
      final h24 = dt.hour;
      final min = dt.minute.toString().padLeft(2, '0');
      final ap  = h24 >= 12 ? 'PM' : 'AM';
      final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
      return '${dt.year}/$m/$d  $h12:$min $ap';
    } catch (_) { return iso; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        appBar: AppBar(
          backgroundColor: const Color(0xFF111111),
          elevation: 0,
          title: const Text('Voice Identification',
              style: TextStyle(color: Colors.white)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildBody()),
              _buildHintBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.initialising:
        return _centreSpinner(Colors.blue, 'Starting up...');
      case _Phase.listening:
        return _buildListeningView();
      case _Phase.processing:
        return _centreSpinner(Colors.blue, 'Identifying...');
      case _Phase.showingResult:
        return _buildResultView();
      case _Phase.error:
        return _buildErrorView();
    }
  }

  // ── Listening view ────────────────────────────────────────────────────────

  Widget _buildListeningView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pulsing mic with double ring
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 180 + _pulseController.value * 24,
                  height: 180 + _pulseController.value * 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue
                        .withOpacity(0.04 + _pulseController.value * 0.06),
                    border: Border.all(
                      color: Colors.blue
                          .withOpacity(0.15 + _pulseController.value * 0.35),
                      width: 1.5,
                    ),
                  ),
                ),
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue
                        .withOpacity(0.08 + _pulseController.value * 0.08),
                    border: Border.all(
                      color: Colors.blue
                          .withOpacity(0.4 + _pulseController.value * 0.4),
                      width: 2.5,
                    ),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    size: 72,
                    color: Colors.blue
                        .withOpacity(0.6 + _pulseController.value * 0.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 36),

          const Text('Listening',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),

          const SizedBox(height: 8),

          Text(
            'Speak clearly for at least 2 seconds',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),

          const SizedBox(height: 32),

          _buildWaveformBar(),

          const SizedBox(height: 24),

          Text(
            'Tap anywhere to identify speaker',
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Animated waveform bar ─────────────────────────────────────────────────

  Widget _buildWaveformBar() {
    final rng = math.Random(42);
    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (i) {
          final minH = 6.0 + rng.nextDouble() * 8;
          final maxH = 22.0 + rng.nextDouble() * 30;
          return AnimatedBuilder(
            animation: _barControllers[i],
            builder: (_, __) {
              final centerFactor = 1.0 -
                  (((i - _barCount / 2).abs()) / (_barCount / 2)) * 0.35;
              final h = (minH + (maxH - minH) * _barControllers[i].value) *
                  centerFactor;
              return Container(
                width: 4,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Color.lerp(
                    Colors.blue.withOpacity(0.4),
                    Colors.lightBlueAccent,
                    _barControllers[i].value,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }

  // ── Result view ───────────────────────────────────────────────────────────

  Widget _buildResultView() {
    if (_lastResult == null) return const SizedBox.shrink();

    final name         = _lastResult!['name'] as String? ?? '';
    final isIdentified = _lastResult!['identified'] as bool? ?? false;
    final confidence   =
        ((_lastResult!['confidence'] ?? 0.0) as num).toDouble();
    final lastSeenIso  = _lastResult!['last_seen'] as String?;

    final isKnown = isIdentified &&
        name.isNotEmpty &&
        name != 'No users registered'         &&
        name != 'Unknown Person Speaking'     &&
        name != "Can't hear someone speaking" &&
        name != 'Error';

    Color    borderColor;
    Color    iconColor;
    IconData icon;
    String   statusLabel;

    if (name == "Can't hear someone speaking" || name.isEmpty) {
      borderColor = Colors.grey.shade700;
      iconColor   = Colors.grey;
      icon        = Icons.volume_off_rounded;
      statusLabel = 'No Voice Detected';
    } else if (!isKnown) {
      borderColor = Colors.orange.shade700;
      iconColor   = Colors.orange;
      icon        = Icons.person_off_rounded;
      statusLabel = 'Unknown Speaker';
    } else if (confidence >= 70) {
      borderColor = Colors.green.shade600;
      iconColor   = Colors.greenAccent;
      icon        = Icons.verified_user_rounded;
      statusLabel = 'Identified!';
    } else {
      borderColor = Colors.blue.shade600;
      iconColor   = Colors.lightBlueAccent;
      icon        = Icons.person_search_rounded;
      statusLabel = 'Possible Match';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Main result card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: borderColor.withOpacity(0.7), width: 2),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 60, color: iconColor),
                ),
                const SizedBox(height: 14),
                Text(statusLabel,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: iconColor)),
                const SizedBox(height: 16),
                if (name.isNotEmpty &&
                    name != "Can't hear someone speaking")
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: iconColor.withOpacity(0.25), width: 1.5),
                    ),
                    child: Text(
                      name,
                      style: TextStyle(
                          fontSize: isKnown ? 30 : 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),

          // Last met card
          if (isKnown) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.purple.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history,
                      color: Colors.purpleAccent, size: 22),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LAST MET',
                          style: TextStyle(
                              color: Colors.purpleAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text(
                        (lastSeenIso != null && lastSeenIso.isNotEmpty)
                            ? _fmt(lastSeenIso)
                            : 'First meeting',
                        style: TextStyle(
                          color: (lastSeenIso != null &&
                                  lastSeenIso.isNotEmpty)
                              ? Colors.white
                              : Colors.grey[500],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text('Listening again shortly...',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ],
      ),
    );
  }

  // ── Error view ────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic_off, size: 80, color: Colors.redAccent),
            const SizedBox(height: 24),
            const Text('Microphone Error',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent)),
            const SizedBox(height: 10),
            Text(
              'Microphone permission is required.\nPlease allow access in device settings.',
              style: TextStyle(color: Colors.red.shade300, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Spinner ───────────────────────────────────────────────────────────────

  Widget _centreSpinner(Color color, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(strokeWidth: 5, color: color),
          ),
          const SizedBox(height: 24),
          Text(label,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ── Bottom hint bar ───────────────────────────────────────────────────────

  Widget _buildHintBar() {
    final String hint;
    switch (_phase) {
      case _Phase.listening:
        hint = '👆 Tap anywhere to stop and identify';
        break;
      case _Phase.processing:
        hint = 'Analysing voice...';
        break;
      case _Phase.showingResult:
        hint = 'Listening again shortly...';
        break;
      default:
        hint = 'Please wait...';
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Text(hint,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
          textAlign: TextAlign.center),
    );
  }
}
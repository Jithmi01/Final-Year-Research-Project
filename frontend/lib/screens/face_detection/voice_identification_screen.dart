// lib/screens/face_detection/voice_identification_screen.dart
//
// ══════════════════════════════════════════════════════════════════════════════
// FULL FLOW (designed for blind users — everything via TTS voice output):
//
//  [A] Screen opens → mic opens → VAD listens continuously
//      TAP during listening/recording → immediately stops & analyses
//
//  [B] Voice captured → backend → TTS announces result:
//        "John identified. Last met on ..."   (known person)
//        "Unknown person detected."           (not registered)
//        "No voice detected."                 (silence / too quiet)
//
//  [C-YES] Translation exists (known person spoke a DIFFERENT language):
//        → TTS AUTOMATICALLY speaks translation in selected language
//        → TTS: "Tap to hear translation again. Double tap to listen."
//        ┌─ SINGLE TAP ──────────────────────────────────────────────────────┐
//        │  TTS speaks translation again in selected language                │
//        │  TTS: "Tap to hear again. Double tap to listen for new voice."   │
//        │  SINGLE TAP again → speaks translation again  (repeats forever) │
//        │  DOUBLE TAP       → back to [A] listening                       │
//        └──────────────────────────────────────────────────────────────────┘
//        DOUBLE TAP at any point → stops TTS, back to [A] listening
//        Auto 12s with no interaction → back to [A] listening
//
//  [C-NO] No translation (same language / unknown / no voice):
//        TTS: "Tap to replay result. Double tap to listen again."
//        SINGLE TAP  → replays full result announcement
//        DOUBLE TAP  → back to [A] listening immediately
//        Auto 12s    → back to [A] listening
//
//  Runs FOREVER until user presses hardware back or AppBar back arrow.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../../services/audio_service.dart';
import '../../services/language_preference_service.dart';
import 'language_settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
enum _Phase {
  initialising,        // Boot: load prefs, set up TTS, get mic permission
  listening,           // VAD active — waiting for voice
  recording,           // Voice detected — capturing
  processing,          // Waiting for backend response
  announcingResult,    // TTS speaking the identification result
  awaitingTranslationTap, // TTS asked "tap to hear translation"
  speakingTranslation, // TTS reading the translated text
  awaitingNextAction,  // Result shown, waiting: single tap=replay, double=restart
  paused,              // Language settings screen open
  error,               // Mic permission denied
}
// ─────────────────────────────────────────────────────────────────────────────

class VoiceIdentificationScreen extends StatefulWidget {
  const VoiceIdentificationScreen({Key? key}) : super(key: key);

  @override
  State<VoiceIdentificationScreen> createState() =>
      _VoiceIdentificationScreenState();
}

class _VoiceIdentificationScreenState extends State<VoiceIdentificationScreen>
    with SingleTickerProviderStateMixin {

  // ── Services ──────────────────────────────────────────────────────────────
  final AudioService _audioService = AudioService();
  final FlutterTts   _tts          = FlutterTts();

  // ── Phase ─────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.initialising;

  // ── Language ──────────────────────────────────────────────────────────────
  LanguageOption _targetLanguage = LanguagePreferenceService.defaultLanguage;

  // ── Last identification result (for display) ──────────────────────────────
  Map<String, dynamic>? _lastResult;

  // ── Translation cache ─────────────────────────────────────────────────────
  String? _translatedText;    // null = no translation for this cycle
  String? _transcribedText;   // original spoken text (for display)
  String? _detectedLang;

  // ── VAD parameters ────────────────────────────────────────────────────────
  static const double _voiceThresholdDb = -35.0;  // dBFS
  static const int    _silenceMs        = 1500;   // ms silence → stop recording
  static const int    _minSpeechMs      = 800;    // ignore bursts shorter than this
  static const int    _maxRecordMs      = 15000;  // safety cap

  // ── Auto-restart after result (if user does nothing) ─────────────────────
  static const int    _autoRestartMs    = 12000;  // 12 s

  // ── VAD runtime ───────────────────────────────────────────────────────────
  StreamSubscription<double>? _amplitudeSub;
  Timer?    _silenceTimer;
  Timer?    _maxRecordTimer;
  Timer?    _autoRestartTimer;
  DateTime? _speechStart;
  bool      _isSpeaking  = false;
  bool      _loopActive  = false;

  // ── TTS busy flag — blocks VAD while TTS is talking ───────────────────────
  bool _ttsBusy       = false;
  bool _ttsInterrupted = false; // set true by double-tap to abort _speakInLang

  // ── UI amplitude ──────────────────────────────────────────────────────────
  double _currentDb = -160.0;

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _pulse;

  // ── Double-tap detection ──────────────────────────────────────────────────
  Timer?   _doubleTapTimer;
  bool     _waitingForDoubleTap = false;
  static const int _doubleTapWindowMs = 400; // ms between taps

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _bootstrap();
  }

  @override
  void dispose() {
    _loopActive = false;
    _amplitudeSub?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _autoRestartTimer?.cancel();
    _doubleTapTimer?.cancel();
    _pulse.dispose();
    _audioService.dispose();
    _tts.stop();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BOOTSTRAP
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _bootstrap() async {
    _setPhase(_Phase.initialising);

    final saved = await LanguagePreferenceService.loadLanguage();
    if (!mounted) return;
    setState(() => _targetLanguage = saved);

    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);

    if (!await _audioService.hasPermission()) {
      final ok = await _audioService.requestPermission();
      if (!ok) { _setPhase(_Phase.error); return; }
    }

    _loopActive = true;
    await _speakWait('Ready. Listening for voice. Tap screen to analyse immediately.');
    if (mounted && _loopActive) _startListening();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LISTENING (VAD)
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _startListening() async {
    if (!mounted || !_loopActive) return;

    // Cancel any pending timers
    _autoRestartTimer?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _amplitudeSub?.cancel();

    _isSpeaking      = false;
    _speechStart     = null;
    _currentDb       = -160.0;
    _ttsInterrupted  = false;

    // Clear translation cache for new cycle
    _translatedText  = null;
    _transcribedText = null;
    _detectedLang    = null;

    _setPhase(_Phase.listening);

    final ok = await _audioService.startRecording();
    if (!ok) {
      _setPhase(_Phase.error);
      await _speakWait('Cannot access microphone.');
      return;
    }

    _amplitudeSub = _audioService.amplitudeStream().listen(_onAmplitude);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // VAD — amplitude handler
  // ════════════════════════════════════════════════════════════════════════════

  void _onAmplitude(double db) {
    if (!mounted || !_loopActive || _ttsBusy) return;
    setState(() => _currentDb = db);

    final voice = db > _voiceThresholdDb;

    if (!_isSpeaking && voice) {
      // ── Voice STARTED ────────────────────────────────────────────────────
      _isSpeaking  = true;
      _speechStart = DateTime.now();
      _silenceTimer?.cancel();
      _setPhase(_Phase.recording);
      _maxRecordTimer?.cancel();
      _maxRecordTimer = Timer(
        const Duration(milliseconds: _maxRecordMs), _finishRecording);

    } else if (_isSpeaking && !voice) {
      // ── Silence started — begin countdown ────────────────────────────────
      _silenceTimer?.cancel();
      _silenceTimer = Timer(
        const Duration(milliseconds: _silenceMs), _finishRecording);

    } else if (_isSpeaking && voice) {
      // Still speaking — reset silence timer
      _silenceTimer?.cancel();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FINISH RECORDING
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _finishRecording() async {
    if (!mounted || !_loopActive) return;

    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _amplitudeSub?.cancel();

    final speechMs = _speechStart == null
        ? 0
        : DateTime.now().difference(_speechStart!).inMilliseconds;

    // Discard noise bursts
    if (!_isSpeaking || speechMs < _minSpeechMs) {
      final p = await _audioService.stopRecording();
      if (p != null) _audioService.deleteAudioFile(p);
      _isSpeaking = false;
      if (_loopActive && mounted) _startListening();
      return;
    }

    final path = await _audioService.stopRecording();
    _isSpeaking = false;

    if (path == null) {
      if (_loopActive && mounted) _startListening();
      return;
    }

    _setPhase(_Phase.processing);

    try {
      final resp = await ApiService.identifyVoiceSpeaker(
        audioFilePath: path,
        targetLanguageCode: _targetLanguage.code,
      );
      await _audioService.deleteAudioFile(path);
      if (!mounted || !_loopActive) return;

      if (resp['success'] == true) {
        final idResult = resp['result'] as Map<String, dynamic>;
        setState(() => _lastResult = idResult);
        await _processResult(idResult);
      } else {
        if (_loopActive && mounted) _startListening();
      }
    } catch (_) {
      await _audioService.deleteAudioFile(path);
      if (mounted && _loopActive) {
        await _speakWait('Connection error. Trying again.');
        _startListening();
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PROCESS RESULT — announce then decide translation flow
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _processResult(Map<String, dynamic> idResult) async {
    final name         = idResult['name'] as String? ?? '';
    final isIdentified = idResult['identified'] as bool? ?? false;
    final lastSeen     = idResult['last_seen'] as String?;

    final isKnown = isIdentified &&
        name.isNotEmpty &&
        name != 'No users registered' &&
        name != 'Unknown Person Speaking' &&
        name != "Can't hear someone speaking" &&
        name != 'Error';

    // ── Check if translation is available ─────────────────────────────────
    final tData        = idResult['translation'] as Map<String, dynamic>?;
    final alreadyTgt   = tData?['is_already_target'] as bool? ?? true;
    final tText        = tData?['translated_text']   as String?;
    final srcText      = tData?['transcribed_text']  as String?;
    final detLang      = tData?['detected_language'] as String?;

    final hasTranslation = isKnown &&
        !alreadyTgt &&
        tText  != null && tText.isNotEmpty &&
        srcText != null && srcText.isNotEmpty;

    if (hasTranslation) {
      _translatedText  = tText;
      _transcribedText = srcText;
      _detectedLang    = detLang;
    } else {
      _translatedText  = null;
      _transcribedText = null;
      _detectedLang    = null;
    }

    // ── Step 1: Announce who was identified via TTS ───────────────────────
    _setPhase(_Phase.announcingResult);
    String announcement;
    if (name == "Can't hear someone speaking" || name.isEmpty) {
      announcement = 'No voice detected.';
    } else if (!isKnown) {
      announcement = 'Unknown person detected.';
    } else {
      if (lastSeen == null || lastSeen.isEmpty) {
        announcement = '$name identified.';
      } else {
        announcement = '$name identified. Last met on ${_fmt(lastSeen)}.';
      }
    }
    await _speakWait(announcement);
    if (!mounted || !_loopActive) return;

    // ── Step 2: Translation flow ──────────────────────────────────────────
    if (hasTranslation) {
      // Speak translation immediately via voice — blind users cannot see text.
      // First speak it, then offer replay option.
      await _speakTranslation();
    } else {
      _setPhase(_Phase.awaitingNextAction);
      await _speakWait('Tap to replay result. Double tap to listen again.');
      if (!mounted || !_loopActive) return;
      _startAutoRestart();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SPEAK TRANSLATION
  // Called on SINGLE TAP when _phase == awaitingTranslationTap.
  // Speaks the translation via TTS in the target language, then via TTS
  // tells the user: tap to hear again, double tap to go back to listening.
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // SPEAK TRANSLATION
  // Speaks translated text via TTS in target language.
  // Called automatically after result announcement AND on every single tap.
  // After speaking, tells user options via voice (tap=repeat, double=skip).
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _speakTranslation() async {
    if (_translatedText == null || _translatedText!.trim().isEmpty) return;
    _autoRestartTimer?.cancel();
    _setPhase(_Phase.speakingTranslation);

    // ── Switch to target language and speak the translation via TTS ───────────
    // We call flutter_tts directly here to guarantee voice output.
    // This is the ONLY place in the app where non-English TTS fires.
    try {
      await _tts.setLanguage(_targetLanguage.ttsLocale);
      await Future.delayed(const Duration(milliseconds: 200)); // let engine switch

      final c = Completer<void>();
      _ttsBusy = true;
      _tts.setCompletionHandler(() {
        _ttsBusy = false;
        if (!c.isCompleted) c.complete();
      });

      await _tts.speak(_translatedText!);

      // Timeout = generous estimate based on text length
      final ms = (_translatedText!.length * 120).clamp(3000, 60000);
      await c.future.timeout(Duration(milliseconds: ms),
          onTimeout: () { _ttsBusy = false; });

    } catch (e) {
      _ttsBusy = false;
    }

    if (!mounted || _ttsInterrupted) return;

    // ── Restore English TTS engine ─────────────────────────────────────────────
    await _tts.setLanguage('en-US');
    await Future.delayed(const Duration(milliseconds: 150));

    // ── Tell user their options via voice ──────────────────────────────────────
    _setPhase(_Phase.awaitingTranslationTap);
    await _speakWait(
      'Tap to hear translation again. Double tap to listen for new voice.',
    );
    if (!mounted || _ttsInterrupted) return;
    _startAutoRestart();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // AUTO-RESTART timer — if user does nothing, restart listening automatically
  // ════════════════════════════════════════════════════════════════════════════

  void _startAutoRestart() {
    _autoRestartTimer?.cancel();
    _autoRestartTimer = Timer(
      const Duration(milliseconds: _autoRestartMs),
      () {
        if (mounted && _loopActive &&
            (_phase == _Phase.awaitingTranslationTap ||
             _phase == _Phase.awaitingNextAction)) {
          _restartListening();
        }
      },
    );
  }

  void _restartListening() {
    _autoRestartTimer?.cancel();
    if (mounted && _loopActive) _startListening();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TAP HANDLER — single vs double tap
  // ════════════════════════════════════════════════════════════════════════════

  void _onTap() {
    // Hard-ignore: truly nothing to do in these states
    if (_phase == _Phase.initialising ||
        _phase == _Phase.paused       ||
        _phase == _Phase.error        ||
        _phase == _Phase.processing) return;

    // ── TAP during LISTENING → stop VAD and force analyse immediately ────────
    if (_phase == _Phase.listening || _phase == _Phase.recording) {
      _amplitudeSub?.cancel();
      _silenceTimer?.cancel();
      _maxRecordTimer?.cancel();
      _finishRecording();   // stop mic + send to backend
      return;
    }

    if (_waitingForDoubleTap) {
      // ── DOUBLE TAP detected ─────────────────────────────────────────────
      _doubleTapTimer?.cancel();
      _waitingForDoubleTap = false;
      _handleDoubleTap();
    } else {
      // First tap — start window to detect second tap
      _waitingForDoubleTap = true;
      _doubleTapTimer = Timer(
        const Duration(milliseconds: _doubleTapWindowMs),
        () {
          _waitingForDoubleTap = false;
          _handleSingleTap();  // No second tap came — it was a single tap
        },
      );
    }
  }

  // ── Single tap logic ──────────────────────────────────────────────────────
  void _handleSingleTap() {
    _autoRestartTimer?.cancel();

    switch (_phase) {
      case _Phase.awaitingTranslationTap:
        // User wants to hear translation → speak it
        _speakTranslation();
        break;

      case _Phase.speakingTranslation:
        // TTS is already reading translation — do nothing, let it finish
        break;

      case _Phase.awaitingNextAction:
        // No translation — user wants to replay the identification result
        _replayLastResult();
        break;

      case _Phase.announcingResult:
        // TTS is announcing result — do nothing, let it finish
        break;

      default:
        break;
    }
  }

  // ── Double tap logic ──────────────────────────────────────────────────────
  // Works from ANY phase after processing — immediately stops TTS and
  // goes back to listening. This is the primary "continue" gesture for
  // blind users who don't need translation or have heard enough.
  void _handleDoubleTap() {
    _autoRestartTimer?.cancel();
    _doubleTapTimer?.cancel();
    // Signal any in-progress _speakInLang to abort after current word
    _ttsInterrupted = true;
    _tts.stop();
    _ttsBusy = false;
    _restartListening();
  }

  // ── Replay last result announcement ──────────────────────────────────────
  Future<void> _replayLastResult() async {
    if (_lastResult == null) return;
    _setPhase(_Phase.announcingResult);
    await _processResult(_lastResult!);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LANGUAGE SETTINGS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _openLanguageSettings() async {
    _loopActive = false;
    _autoRestartTimer?.cancel();
    _amplitudeSub?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _doubleTapTimer?.cancel();
    _waitingForDoubleTap = false;
    await _tts.stop();
    _ttsBusy = false;
    await _audioService.stopRecording()
        .then((p) { if (p != null) _audioService.deleteAudioFile(p); });
    _setPhase(_Phase.paused);

    final result = await Navigator.push<LanguageOption>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              LanguageSettingsScreen(currentLanguage: _targetLanguage)),
    );
    if (!mounted) return;
    if (result != null) setState(() => _targetLanguage = result);

    _loopActive = true;
    await _tts.setLanguage('en-US');
    await _speakWait(
      'Language set to ${result?.englishName ?? _targetLanguage.englishName}. Listening.',
    );
    if (mounted && _loopActive) _startListening();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  void _setPhase(_Phase p) { if (mounted) setState(() => _phase = p); }

  /// Speak [text] in [locale] and WAIT for TTS to fully finish before returning.
  /// Safe to call for any locale — restores 'en-US' when done.
  /// Does NOT guard on _loopActive so TTS always completes even mid-cycle.
  Future<void> _speakInLang(String text, {String locale = 'en-US'}) async {
    if (!mounted || text.trim().isEmpty) return;
    // NOTE: _ttsInterrupted is NOT reset here — it is only reset in
    // _startListening() so a double-tap during any speech in the result
    // cycle correctly aborts ALL subsequent speech in that cycle.

    final c = Completer<void>();
    _ttsBusy = true;

    // Register completion handler BEFORE setLanguage / speak
    _tts.setCompletionHandler(() {
      _ttsBusy = false;
      if (!c.isCompleted) c.complete();
    });

    // Switch language
    await _tts.setLanguage(locale);

    // Android needs a short pause after setLanguage before speak()
    // otherwise it sometimes speaks in the wrong engine/locale
    await Future.delayed(const Duration(milliseconds: 150));

    // Abort if double-tap interrupted during the language-switch delay
    if (!mounted || _ttsInterrupted) { _ttsBusy = false; return; }

    await _tts.speak(text);

    // Wait for TTS to finish — timeout scales with text length
    final timeoutMs = ((text.length / 10) * 600).clamp(4000, 45000).toInt();
    await c.future.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () { _ttsBusy = false; },
    );

    // Always restore English so subsequent en-US speech works correctly
    if (locale != 'en-US') {
      await _tts.setLanguage('en-US');
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Speak in English and wait — shorthand used everywhere.
  Future<void> _speakWait(String text) =>
      _speakInLang(text, locale: 'en-US');

  String _fmt(String iso) {
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final m    = dt.month.toString().padLeft(2, '0');
      final d    = dt.day.toString().padLeft(2, '0');
      final h24  = dt.hour;
      final min  = dt.minute.toString().padLeft(2, '0');
      final ampm = h24 >= 12 ? 'PM' : 'AM';
      final h12  = h24 % 12 == 0 ? 12 : h24 % 12;
      return '${dt.year}/$m/$d  $h12:$min $ampm';
    } catch (_) { return iso; }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        title: const Text('Voice Identification',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () { _loopActive = false; Navigator.pop(context); },
        ),
        actions: [
          GestureDetector(
            onTap: _openLanguageSettings,
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.tealAccent.withOpacity(0.5), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_targetLanguage.flag,
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 5),
                  Text(_targetLanguage.englishName,
                      style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down,
                      color: Colors.tealAccent, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Whole body = tap detector ──────────────────────────────────────────
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: SafeArea(
          child: Column(
            children: [
              // Translation pill
              GestureDetector(
                onTap: _openLanguageSettings,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.teal.withOpacity(0.25), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.translate,
                          color: Colors.tealAccent, size: 13),
                      const SizedBox(width: 6),
                      Text(
                        'Translating to  ${_targetLanguage.flag} '
                        '${_targetLanguage.englishName}  •  tap to change',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              // Main content
              Expanded(child: _buildBody()),

              // Bottom gesture hint
              _buildGestureHint(),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BODY — switches based on _phase
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.initialising:
        return _centreCard(
          icon: Icons.settings_outlined,
          color: Colors.blue,
          title: 'Starting up...',
          sub: 'Loading settings and microphone',
          spinner: true,
        );

      case _Phase.listening:
        return _buildListeningView();

      case _Phase.recording:
        return _buildRecordingView();

      case _Phase.processing:
        return _centreCard(
          icon: Icons.psychology_outlined,
          color: Colors.blue,
          title: 'Identifying...',
          sub: 'Analysing voice patterns',
          spinner: true,
        );

      case _Phase.announcingResult:
        return _buildResultView(announcing: true);

      case _Phase.awaitingTranslationTap:
        return _buildTranslationPromptView();

      case _Phase.speakingTranslation:
        return _buildSpeakingTranslationView();

      case _Phase.awaitingNextAction:
        return _buildResultView(announcing: false);

      case _Phase.paused:
        return _centreCard(
          icon: Icons.pause_circle_outline,
          color: Colors.grey,
          title: 'Paused',
          sub: 'Close settings to resume',
        );

      case _Phase.error:
        return _buildErrorView();
    }
  }

  // ── Listening ─────────────────────────────────────────────────────────────
  Widget _buildListeningView() {
    final bar = ((_currentDb + 160) / 160).clamp(0.0, 1.0).toDouble();
    final nearThr = _currentDb > (_voiceThresholdDb - 10);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.teal.withOpacity(
                    0.04 + _pulse.value * 0.08),
                border: Border.all(
                  color: Colors.teal.withOpacity(
                      0.25 + _pulse.value * 0.45),
                  width: 2.5,
                ),
              ),
              child: Icon(Icons.hearing_rounded,
                  size: 90,
                  color: Colors.teal.withOpacity(
                      0.5 + _pulse.value * 0.5)),
            ),
          ),
          const SizedBox(height: 30),
          const Text('Listening...',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.tealAccent)),
          const SizedBox(height: 10),
          Text('Speak clearly — auto-detects voice, or tap to analyse now',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Voice level',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              Text(nearThr ? 'Speak louder...' : 'Ready',
                  style: TextStyle(
                    color: nearThr ? Colors.orange : Colors.grey[600],
                    fontSize: 12,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: bar,
              minHeight: 14,
              backgroundColor: Colors.grey[900],
              valueColor: AlwaysStoppedAnimation<Color>(
                bar > 0.55 ? Colors.tealAccent : Colors.teal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recording ─────────────────────────────────────────────────────────────
  Widget _buildRecordingView() {
    final bar = ((_currentDb + 160) / 160).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Transform.scale(
              scale: 1.0 + _pulse.value * 0.2,
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(
                      0.08 + _pulse.value * 0.12),
                  border: Border.all(
                    color: Colors.red.withOpacity(
                        0.4 + _pulse.value * 0.4),
                    width: 2.5,
                  ),
                ),
                child: Icon(Icons.mic_rounded,
                    size: 90,
                    color: Colors.red.withOpacity(
                        0.6 + _pulse.value * 0.4)),
              ),
            ),
          ),
          const SizedBox(height: 30),
          const Text('Recording',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent)),
          const SizedBox(height: 10),
          Text('Tap to analyse now, or pause speaking to auto-stop',
              style: TextStyle(
                  fontSize: 14, color: Colors.red.shade300),
              textAlign: TextAlign.center),
          const SizedBox(height: 36),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: bar,
              minHeight: 14,
              backgroundColor: Colors.red.shade900.withOpacity(0.3),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  // ── Result view ───────────────────────────────────────────────────────────
  Widget _buildResultView({required bool announcing}) {
    if (_lastResult == null) return const SizedBox.shrink();

    final name         = _lastResult!['name'] as String? ?? '';
    final isIdentified = _lastResult!['identified'] as bool? ?? false;
    final confidence   = ((_lastResult!['confidence'] ?? 0.0) as num).toDouble();
    final lastSeenIso  = _lastResult!['last_seen'] as String?;

    final isKnown = isIdentified &&
        name.isNotEmpty &&
        name != 'No users registered' &&
        name != 'Unknown Person Speaking' &&
        name != "Can't hear someone speaking" &&
        name != 'Error';

    Color  bdrColor;
    Color  iconColor;
    IconData icon;
    String status;

    if (name == "Can't hear someone speaking" || name.isEmpty) {
      bdrColor = Colors.grey.shade700;
      iconColor = Colors.grey;
      icon     = Icons.volume_off_rounded;
      status   = 'No Voice Detected';
    } else if (!isKnown) {
      bdrColor = Colors.orange.shade700;
      iconColor = Colors.orange;
      icon     = Icons.person_off_rounded;
      status   = 'Unknown Speaker';
    } else if (confidence >= 70) {
      bdrColor = Colors.green.shade600;
      iconColor = Colors.greenAccent;
      icon     = Icons.verified_user_rounded;
      status   = 'Identified!';
    } else {
      bdrColor = Colors.blue.shade600;
      iconColor = Colors.lightBlueAccent;
      icon     = Icons.person_search_rounded;
      status   = 'Possible Match';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          // ── Main result block ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: bdrColor.withOpacity(0.7), width: 2),
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
                Text(status,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: iconColor)),
                const SizedBox(height: 6),

                // TTS activity indicator
                if (announcing)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: iconColor.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Speaking...',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12)),
                    ],
                  ),

                const SizedBox(height: 16),

                // Name badge
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
                    child: Text(name,
                        style: TextStyle(
                            fontSize: isKnown ? 28 : 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                        textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),

          // ── Last Met ─────────────────────────────────────────────────────
          if (isKnown) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.purple.withOpacity(0.35), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history,
                      color: Colors.purpleAccent, size: 22),
                  const SizedBox(width: 12),
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

          // ── Translation teaser (only when available) ──────────────────
          if (_translatedText != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.teal.withOpacity(0.35), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.translate,
                      color: Colors.tealAccent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Translation available  •  '
                          '${_targetLanguage.flag} ${_targetLanguage.englishName}',
                          style: const TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Single tap to hear  •  Double tap to skip',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Tap hint when no translation ──────────────────────────────
          if (_translatedText == null && !announcing) ...[
            const SizedBox(height: 16),
            Text('Single tap to replay  •  Double tap to listen again',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  // ── Translation prompt ────────────────────────────────────────────────────
  Widget _buildTranslationPromptView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.teal.withOpacity(
                    0.06 + _pulse.value * 0.08),
                border: Border.all(
                  color: Colors.teal.withOpacity(
                      0.3 + _pulse.value * 0.4),
                  width: 2.5,
                ),
              ),
              child: Icon(Icons.touch_app_rounded,
                  size: 80,
                  color: Colors.teal.withOpacity(
                      0.5 + _pulse.value * 0.5)),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Translation Spoken',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.tealAccent)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.teal.withOpacity(0.3), width: 1),
            ),
            child: Column(
              children: [
                _gestureRow(
                  icon: Icons.touch_app,
                  color: Colors.tealAccent,
                  label: 'Single tap',
                  desc: 'Hear translation again in ${_targetLanguage.englishName}',
                ),
                const SizedBox(height: 10),
                _gestureRow(
                  icon: Icons.touch_app,
                  color: Colors.orange,
                  label: 'Double tap',
                  desc: 'Listen for new voice',
                ),
              ],
            ),
          ),
          if (_transcribedText != null) ...[
            const SizedBox(height: 20),
            Text('"$_transcribedText"',
                style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 13,
                    fontStyle: FontStyle.italic),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  // ── Speaking translation ──────────────────────────────────────────────────
  Widget _buildSpeakingTranslationView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Transform.scale(
              scale: 1.0 + _pulse.value * 0.15,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.withOpacity(
                      0.08 + _pulse.value * 0.1),
                  border: Border.all(
                    color: Colors.tealAccent.withOpacity(
                        0.4 + _pulse.value * 0.4),
                    width: 2.5,
                  ),
                ),
                child: Icon(Icons.volume_up_rounded,
                    size: 80,
                    color: Colors.tealAccent.withOpacity(
                        0.6 + _pulse.value * 0.4)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text('Speaking in ${_targetLanguage.englishName}...',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.tealAccent)),
          const SizedBox(height: 12),
          if (_translatedText != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _translatedText!,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 16, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────
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
              'Microphone permission is required.\n'
              'Please allow access in device Settings.',
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

  // ── Generic centred card ──────────────────────────────────────────────────
  Widget _centreCard({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    bool spinner = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            spinner
                ? SizedBox(
                    width: 80, height: 80,
                    child: CircularProgressIndicator(
                        strokeWidth: 5, color: color))
                : Icon(icon, size: 80, color: color),
            const SizedBox(height: 24),
            Text(title,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 8),
            Text(sub,
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Bottom gesture hint bar ───────────────────────────────────────────────
  Widget _buildGestureHint() {
    String hint;
    switch (_phase) {
      case _Phase.listening:
      case _Phase.recording:
        hint = '👆 Tap to stop & analyse now   (auto-detects silence)';
        break;
      case _Phase.awaitingTranslationTap:
        hint = '👆 Single tap = hear translation again   👆👆 Double tap = listen for new voice';
        break;
      case _Phase.awaitingNextAction:
        hint = '👆 Single tap = replay result   👆👆 Double tap = listen again';
        break;
      case _Phase.speakingTranslation:
        hint = '👆👆 Double tap = stop & listen again';
        break;
      default:
        hint = '👆👆 Double tap anywhere to restart listening';
    }

    return Container(
      width: double.infinity,
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Text(hint,
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
          textAlign: TextAlign.center),
    );
  }

  // ── Gesture row helper ────────────────────────────────────────────────────
  Widget _gestureRow({
    required IconData icon,
    required Color color,
    required String label,
    required String desc,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                  text: '$label  ',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              TextSpan(
                  text: desc,
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
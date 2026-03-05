// lib/services/language_preference_service.dart
// Persists the user's chosen target translation language across app restarts.
// Uses shared_preferences so the selection survives even after the app is closed.

import 'package:shared_preferences/shared_preferences.dart';

class LanguagePreferenceService {
  static const String _kLangCode = 'target_language_code';
  static const String _kLangName = 'target_language_name';
  static const String _kLangFlag = 'target_language_flag';

  // Default: Sinhala
  static const LanguageOption defaultLanguage = LanguageOption(
    code: 'si',
    name: 'සිංහල',
    englishName: 'Sinhala',
    flag: '🇱🇰',
    ttsLocale: 'si-LK',
  );

  /// Save the selected language to persistent storage.
  static Future<void> saveLanguage(LanguageOption lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangCode, lang.code);
    await prefs.setString(_kLangName, lang.name);
    await prefs.setString(_kLangFlag, lang.flag);
  }

  /// Load the previously saved language. Returns [defaultLanguage] if nothing saved.
  static Future<LanguageOption> loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLangCode);
    if (code == null) return defaultLanguage;

    // Find matching option from the full list
    return supportedLanguages.firstWhere(
      (l) => l.code == code,
      orElse: () => defaultLanguage,
    );
  }

  /// All supported target languages.
  static const List<LanguageOption> supportedLanguages = [
    LanguageOption(code: 'si', name: 'සිංහල',      englishName: 'Sinhala',    flag: '🇱🇰', ttsLocale: 'si-LK'),
    LanguageOption(code: 'en', name: 'English',     englishName: 'English',    flag: '🇬🇧', ttsLocale: 'en-US'),
    LanguageOption(code: 'ta', name: 'தமிழ்',       englishName: 'Tamil',      flag: '🇮🇳', ttsLocale: 'ta-IN'),
    LanguageOption(code: 'hi', name: 'हिन्दी',      englishName: 'Hindi',      flag: '🇮🇳', ttsLocale: 'hi-IN'),
    LanguageOption(code: 'zh-CN', name: '中文',     englishName: 'Chinese',    flag: '🇨🇳', ttsLocale: 'zh-CN'),
    LanguageOption(code: 'ar', name: 'العربية',     englishName: 'Arabic',     flag: '🇸🇦', ttsLocale: 'ar-SA'),
    LanguageOption(code: 'fr', name: 'Français',    englishName: 'French',     flag: '🇫🇷', ttsLocale: 'fr-FR'),
    LanguageOption(code: 'de', name: 'Deutsch',     englishName: 'German',     flag: '🇩🇪', ttsLocale: 'de-DE'),
    LanguageOption(code: 'ja', name: '日本語',       englishName: 'Japanese',   flag: '🇯🇵', ttsLocale: 'ja-JP'),
    LanguageOption(code: 'ko', name: '한국어',       englishName: 'Korean',     flag: '🇰🇷', ttsLocale: 'ko-KR'),
    LanguageOption(code: 'es', name: 'Español',     englishName: 'Spanish',    flag: '🇪🇸', ttsLocale: 'es-ES'),
    LanguageOption(code: 'pt', name: 'Português',   englishName: 'Portuguese', flag: '🇵🇹', ttsLocale: 'pt-PT'),
    LanguageOption(code: 'ru', name: 'Русский',     englishName: 'Russian',    flag: '🇷🇺', ttsLocale: 'ru-RU'),
    LanguageOption(code: 'it', name: 'Italiano',    englishName: 'Italian',    flag: '🇮🇹', ttsLocale: 'it-IT'),
    LanguageOption(code: 'ms', name: 'Melayu',      englishName: 'Malay',      flag: '🇲🇾', ttsLocale: 'ms-MY'),
  ];
}

/// Immutable value object representing one language option.
class LanguageOption {
  final String code;         // deep-translator / Google Translate code
  final String name;         // Native script name shown in UI
  final String englishName;  // English name for accessibility
  final String flag;         // Emoji flag
  final String ttsLocale;    // BCP-47 locale for flutter_tts

  const LanguageOption({
    required this.code,
    required this.name,
    required this.englishName,
    required this.flag,
    required this.ttsLocale,
  });

  @override
  bool operator ==(Object other) =>
      other is LanguageOption && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$flag $name ($englishName)';
}
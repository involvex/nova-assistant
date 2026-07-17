import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Speaks assistant responses via platform TTS.
class TtsService {
  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();
  TtsService._();

  static const _enabledKey = 'settings_tts_enabled';

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  bool _enabled = true;

  bool get isSpeaking => _speaking;
  bool get isEnabled => _enabled;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;

    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((msg) {
      debugPrint('TtsService error: $msg');
      _speaking = false;
    });

    _initialized = true;
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!enabled) await stop();
  }

  Future<void> speak(String text) async {
    if (!_initialized) await initialize();
    if (!_enabled) return;
    final cleaned = _stripMarkdown(text).trim();
    if (cleaned.isEmpty) return;

    await stop();
    await _tts.speak(cleaned);
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await _tts.stop();
    _speaking = false;
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`]+`'), ' ')
        .replaceAll(RegExp(r'[#*_>~\[\]()]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

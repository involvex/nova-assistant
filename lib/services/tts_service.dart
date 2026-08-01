import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Speaks assistant responses via on-device TTS (Matcha via flutter_gemma).
// ignore_for_file: experimental_member_use
class TtsService {
  static TtsService? _instance;
  static TtsService get instance => _instance ??= TtsService._();
  TtsService._();

  static const _enabledKey = 'settings_tts_enabled';
  static const _modelInstalledKey = 'settings_tts_model_installed';

  static const _ttsModelUrl =
      'https://huggingface.co/litert-community/Matcha-TTS/resolve/main/';

  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  bool _speaking = false;
  bool _enabled = true;
  // ignore: unused_field
  StreamSubscription<PlayerState>? _playerStateSub;

  bool get isSpeaking => _speaking;
  bool get isEnabled => _enabled;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? true;

    try {
      await FlutterGemma.initialize(ttsBackends: [LiteRtTtsBackend()]);
    } on Exception catch (e) {
      debugPrint('TtsService: backend init failed: $e');
    }

    _playerStateSub = _player.playerStateStream.listen((state) {
      _speaking = state.playing;
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

    try {
      await _ensureModelInstalled();
      final synth = await FlutterGemma.getActiveTts();
      final pcm = await synth.synthesize(cleaned);
      await _playPcm(pcm, synth.sampleRate);
      await synth.close();
    } on Exception catch (e) {
      debugPrint('TtsService.speak failed: $e');
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await _player.stop();
    _speaking = false;
  }

  Future<void> _ensureModelInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_modelInstalledKey) ?? false) {
      try {
        await FlutterGemma.getActiveTts();
        return;
      } on Exception {
        await prefs.setBool(_modelInstalledKey, false);
      }
    }

    try {
      await FlutterGemma.installTts()
          .fromNetwork(_ttsModelUrl)
          .ofType(TtsModelType.matcha)
          .install();
      await prefs.setBool(_modelInstalledKey, true);
    } on Exception catch (e) {
      debugPrint('TtsService: model install failed: $e');
      rethrow;
    }
  }

  Future<void> _playPcm(Uint8List pcm, int sampleRate) async {
    final wav = _wrapPcmInWav(pcm, sampleRate);
    await _player.setAudioSource(_BytesAudioSource(wav));
    await _player.play();
  }

  Uint8List _wrapPcmInWav(
    Uint8List pcm,
    int sampleRate, {
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final fileSize = 36 + dataSize;

    final header = BytesBuilder()
      ..add(_ascii('RIFF'))
      ..add(_uint32Le(fileSize))
      ..add(_ascii('WAVE'))
      ..add(_ascii('fmt '))
      ..add(_uint32Le(16))
      ..add(_uint16Le(1))
      ..add(_uint16Le(channels))
      ..add(_uint32Le(sampleRate))
      ..add(_uint32Le(byteRate))
      ..add(_uint16Le(blockAlign))
      ..add(_uint16Le(bitsPerSample))
      ..add(_ascii('data'))
      ..add(_uint32Le(dataSize));

    return Uint8List.fromList([...header.toBytes(), ...pcm]);
  }

  Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

  Uint8List _uint32Le(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  Uint8List _uint16Le(int value) {
    final b = ByteData(2)..setUint16(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`]+`'), ' ')
        .replaceAll(RegExp(r'[#*_>~\[\]()]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _BytesAudioSource extends StreamAudioSource {
  _BytesAudioSource(this._bytes);

  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

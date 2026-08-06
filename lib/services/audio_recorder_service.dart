import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class AudioRecorderService {
  static AudioRecorderService? _instance;
  static AudioRecorderService get instance =>
      _instance ??= AudioRecorderService._();

  AudioRecorderService._();

  final AudioRecorder _recorder = AudioRecorder();

  final _stateController = StreamController<RecordingState>.broadcast();
  Stream<RecordingState> get onStateChanged => _stateController.stream;

  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;

  String? _lastRecordingPath;
  String? get lastRecordingPath => _lastRecordingPath;

  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  Future<String?> startRecording() async {
    if (_state != RecordingState.idle) return null;

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      debugPrint('AudioRecorderService: no microphone permission');
      _stateController.add(RecordingState.error);
      return null;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/nova_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _lastRecordingPath = path;

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _recorder.start(config, path: path);

      _recordingDuration = Duration.zero;
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _recordingDuration += const Duration(seconds: 1);
        _stateController.add(RecordingState.recording);
      });

      _state = RecordingState.recording;
      _stateController.add(RecordingState.recording);

      return path;
    } catch (e) {
      debugPrint('AudioRecorderService: start error: $e');
      _state = RecordingState.error;
      _stateController.add(RecordingState.error);
      return null;
    }
  }

  Future<String?> stopRecording() async {
    if (_state != RecordingState.recording && _state != RecordingState.paused) {
      return _lastRecordingPath;
    }

    _durationTimer?.cancel();
    _durationTimer = null;

    try {
      final path = await _recorder.stop();
      _state = RecordingState.idle;
      _stateController.add(RecordingState.idle);

      if (path != null) {
        _lastRecordingPath = path;
      }

      return _lastRecordingPath;
    } catch (e) {
      debugPrint('AudioRecorderService: stop error: $e');
      _state = RecordingState.error;
      _stateController.add(RecordingState.error);
      return _lastRecordingPath;
    }
  }

  Future<void> pauseRecording() async {
    if (_state != RecordingState.recording) return;

    _durationTimer?.cancel();
    try {
      await _recorder.pause();
      _state = RecordingState.paused;
      _stateController.add(RecordingState.paused);
    } catch (e) {
      debugPrint('AudioRecorderService: pause error: $e');
    }
  }

  Future<void> resumeRecording() async {
    if (_state != RecordingState.paused) return;

    try {
      await _recorder.resume();
      _state = RecordingState.recording;
      _stateController.add(RecordingState.recording);
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _recordingDuration += const Duration(seconds: 1);
        _stateController.add(RecordingState.recording);
      });
    } catch (e) {
      debugPrint('AudioRecorderService: resume error: $e');
    }
  }

  bool get isRecording => _state == RecordingState.recording;

  String get formattedDuration {
    final d = _recordingDuration;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  Stream<Amplitude>? get amplitudeStream =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  void dispose() {
    _durationTimer?.cancel();
    _stateController.close();
    _recorder.dispose();
    _instance = null;
  }
}

enum RecordingState { idle, recording, paused, error }

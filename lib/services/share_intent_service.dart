import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Normalizes subject + body from an Android share intent into one prompt.
String? normalizeSharedText({String? subject, String? text}) {
  final trimmedText = text?.trim() ?? '';
  final trimmedSubject = subject?.trim() ?? '';

  if (trimmedText.isEmpty && trimmedSubject.isEmpty) {
    return null;
  }
  if (trimmedText.isEmpty) {
    return trimmedSubject;
  }
  if (trimmedSubject.isEmpty || trimmedText.contains(trimmedSubject)) {
    return trimmedText;
  }

  return '$trimmedSubject\n$trimmedText';
}

/// Receives inbound Android ACTION_SEND text/URL shares.
class ShareIntentService {
  ShareIntentService._();

  static ShareIntentService? _instance;
  static ShareIntentService get instance =>
      _instance ??= ShareIntentService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'dev.nova.assistant/share',
  );
  static const EventChannel _eventChannel = EventChannel(
    'dev.nova.assistant/share_events',
  );

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _eventSub;
  bool _initialized = false;
  String? _lastShared;
  DateTime? _lastSharedAt;
  static const _debounceMs = 1000;

  /// Shared text/URL payloads to open in chat.
  Stream<String> get shareStream => _controller.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
          _emit(event);
        }
      },
      onError: (Object error) {
        debugPrint('Share intent stream error: $error');
      },
    );

    try {
      final pending = await _methodChannel.invokeMethod<String>(
        'getPendingShare',
      );
      if (pending != null && pending.trim().isNotEmpty) {
        _emit(pending.trim());
      }
    } on MissingPluginException {
      // Non-Android / tests without the channel.
    } on PlatformException catch (e) {
      debugPrint('getPendingShare failed: ${e.message}');
    }
  }

  void _emit(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    if (text == _lastShared &&
        _lastSharedAt != null &&
        now.difference(_lastSharedAt!).inMilliseconds < _debounceMs) {
      return;
    }

    _lastShared = text;
    _lastSharedAt = now;
    if (!_controller.isClosed) {
      _controller.add(text);
    }
  }

  @visibleForTesting
  void emitForTest(String text) => _emit(text);

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    if (!_controller.isClosed) {
      _controller.close();
    }
    _initialized = false;
    _instance = null;
  }
}

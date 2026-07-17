import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads process memory usage for debug overlays.
class MemoryDiagnosticsService {
  static MemoryDiagnosticsService? _instance;
  static MemoryDiagnosticsService get instance =>
      _instance ??= MemoryDiagnosticsService._();
  MemoryDiagnosticsService._();

  static const _channel = MethodChannel('dev.nova.assistant/diagnostics');

  int? _lastPssKb;
  int? _lastRssKb;

  int? get lastPssMb =>
      _lastPssKb != null ? (_lastPssKb! / 1024).round() : null;
  int? get lastRssMb =>
      _lastRssKb != null ? (_lastRssKb! / 1024).round() : null;

  /// Best-effort process memory in MB (PSS preferred on Android).
  Future<int?> readProcessMemoryMb() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<Map<Object?, Object?>>(
          'getProcessMemory',
        );
        if (result != null) {
          _lastPssKb = result['pssKb'] as int?;
          _lastRssKb = result['rssKb'] as int?;
          final pss = _lastPssKb;
          if (pss != null) return (pss / 1024).round();
        }
      } on PlatformException catch (e) {
        debugPrint('MemoryDiagnosticsService: $e');
      }
    }

    try {
      final rss = ProcessInfo.currentRss;
      _lastRssKb = rss ~/ 1024;
      return (rss / (1024 * 1024)).round();
    } catch (e) {
      debugPrint('MemoryDiagnosticsService fallback failed: $e');

      return null;
    }
  }
}

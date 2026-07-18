import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Debug-mode NDJSON logger for session 7abc09.
/// Posts to the local ingest server (use `adb reverse tcp:7704 tcp:7704`).
class AgentDebugLog {
  static const _endpoint =
      'http://127.0.0.1:7704/ingest/b12c34e9-d2e1-4829-bc46-cbd81f2bb686';
  static const _sessionId = '7abc09';

  static Future<void> log({
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
    String runId = 'pre-fix',
  }) async {
    final payload = <String, Object?>{
      'sessionId': _sessionId,
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    // #region agent log
    debugPrint('AGENT_DBG ${jsonEncode(payload)}');
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse(_endpoint));
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('X-Debug-Session-Id', _sessionId);
      req.add(utf8.encode(jsonEncode(payload)));
      await req.close().timeout(const Duration(seconds: 2));
      client.close(force: true);
    } catch (_) {
      // Ingest may be unreachable without adb reverse; logcat still has AGENT_DBG.
    }
    // #endregion
  }
}

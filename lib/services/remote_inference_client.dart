import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nova_assistant/services/remote_inference_config.dart';

/// OpenAI-compatible streaming client for LAN hosts (llama-server, etc.).
class RemoteInferenceClient {
  RemoteInferenceClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  /// Parses one SSE `data:` line into a text delta, or null for [DONE]/empty.
  static String? parseSseData(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('data:')) return null;

    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final delta = first['delta'];
      if (delta is Map && delta['content'] is String) {
        final content = delta['content'] as String;

        return content.isEmpty ? null : content;
      }
      // Non-stream chunk shape
      final message = first['message'];
      if (message is Map && message['content'] is String) {
        final content = message['content'] as String;

        return content.isEmpty ? null : content;
      }
    } on FormatException {
      return null;
    }

    return null;
  }

  /// Yields text deltas from OpenAI-style SSE (`data: {...}`).
  Stream<String> streamChat({
    required RemoteInferenceConfig config,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
  }) async* {
    final request = await _httpClient.postUrl(config.chatCompletionsUri());
    config.headers().forEach(request.headers.set);
    final body = jsonEncode({
      'model': config.modelId,
      'stream': true,
      'temperature': temperature,
      'messages': messages,
    });
    request.add(utf8.encode(body));

    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.transform(utf8.decoder).join();
      throw HttpException(
        'Remote inference failed (${response.statusCode}): $errorBody',
        uri: config.chatCompletionsUri(),
      );
    }

    var buffer = '';
    await for (final chunk in response.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final newline = buffer.indexOf('\n');
        if (newline < 0) break;
        final line = buffer.substring(0, newline);
        buffer = buffer.substring(newline + 1);
        final delta = parseSseData(line);
        if (delta != null) yield delta;
      }
    }

    if (buffer.trim().isNotEmpty) {
      final delta = parseSseData(buffer);
      if (delta != null) yield delta;
    }
  }

  /// Lightweight connectivity check against `/v1/models`.
  Future<bool> testConnection(RemoteInferenceConfig config) async {
    try {
      final request = await _httpClient.getUrl(config.modelsUri());
      config.headers().forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();

      return response.statusCode >= 200 && response.statusCode < 300;
    } on Exception {
      return false;
    }
  }

  void close() {
    _httpClient.close(force: true);
  }
}

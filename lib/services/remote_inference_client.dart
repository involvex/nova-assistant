import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';

/// OpenAI-compatible streaming client for LAN hosts (llama-server, etc.).
class RemoteInferenceClient {
  RemoteInferenceClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  /// Upper bound for `/models` bodies. A catalog is a few KB; anything
  /// larger is a misbehaving proxy — fail closed instead of OOMing the
  /// isolate with an unbounded `join()`.
  static const int maxCatalogBodyBytes = 256 * 1024;

  /// Upper bound for parsed catalog entries. Guards the O(n²) dedupe path
  /// and absurd provider responses.
  static const int maxModelIds = 1000;

  /// Entries longer than this are skipped (poison-pill ids).
  static const int maxModelIdLength = 200;

  /// User-visible error preview length. Full bodies go to `debugPrint` only.
  static const int maxErrorPreviewChars = 120;

  /// Upper bound for a single SSE line buffer in [streamChat].
  static const int maxSseBufferChars = 1024 * 1024;

  /// Validates a user-configured base URL and returns it as a [Uri].
  ///
  /// Throws [ArgumentError] for empty values, unparseable URLs, non-HTTP(S)
  /// schemes (e.g. `file://`, `ftp://`), missing hosts, or embedded
  /// credentials (`https://user:pass@host`). `http` stays allowed — LAN
  /// hosts (llama-server/Ollama) are plain HTTP by default.
  static Uri validateBaseUrl(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Remote base URL is empty');
    }
    final Uri? parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasAuthority) {
      throw ArgumentError('Remote base URL is not a valid URL');
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw ArgumentError(
        'Remote base URL must use http or https (got ${parsed.scheme})',
      );
    }
    if (parsed.host.isEmpty) {
      throw ArgumentError('Remote base URL has no host');
    }
    if (parsed.userInfo.isNotEmpty) {
      throw ArgumentError('Remote base URL must not embed credentials');
    }
    return parsed;
  }

  /// True for literal private/loopback/link-local hosts (`192.168.x`,
  /// `10/8`, `172.16/12`, `127/8`, `169.254/16`, `localhost`, `::1`,
  /// `fc00::/7`, `fe80::/10`, `*.local/.lan/.internal`).
  ///
  /// DNS names that are not obviously local return false — resolving them
  /// would require network I/O. Cloud callers that must stay off-LAN should
  /// resolve + re-check before sending tokens.
  static bool isPrivateIpHost(String host) {
    var h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }
    if (h == 'localhost') return true;
    if (h.endsWith('.local') ||
        h.endsWith('.lan') ||
        h.endsWith('.internal') ||
        h.endsWith('.localhost')) {
      return true;
    }
    if (h.contains(':')) {
      if (h == '::1' || h == '::ffff:127.0.0.1') return true;
      if (h.startsWith('fc') || h.startsWith('fd')) return true;
      if (h.startsWith('fe80')) return true;
      if (h.startsWith('::ffff:')) {
        return isPrivateIpHost(h.substring('::ffff:'.length));
      }
      return false;
    }
    final RegExp ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final RegExpMatch? m = ipv4.firstMatch(h);
    if (m == null) return false;
    final List<int?> parts = <int?>[
      int.tryParse(m.group(1)!),
      int.tryParse(m.group(2)!),
      int.tryParse(m.group(3)!),
      int.tryParse(m.group(4)!),
    ];
    if (parts.any((int? p) => p == null || p < 0 || p > 255)) return false;
    final int a = parts[0]!;
    final int b = parts[1]!;
    if (a == 10) return true;
    if (a == 127) return true;
    if (a == 0) return true;
    if (a == 169 && b == 254) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;
    return false;
  }

  /// Collapses whitespace/newlines and truncates for user-visible errors.
  /// Full bodies are logged with `debugPrint` at the call site instead.
  static String sanitizeErrorPreview(
    String body, {
    int maxChars = maxErrorPreviewChars,
  }) {
    final String collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxChars) return collapsed;
    return '${collapsed.substring(0, maxChars)}…';
  }

  /// Reads [byteStream] up to [maxBytes] and decodes it as UTF-8.
  /// Throws when the peer exceeds the bound (fail closed, no OOM).
  @visibleForTesting
  static Future<String> readBoundedBody(
    Stream<List<int>> byteStream, {
    int maxBytes = maxCatalogBodyBytes,
  }) async {
    int seen = 0;
    final BytesBuilder out = BytesBuilder();
    await for (final List<int> chunk in byteStream) {
      seen += chunk.length;
      if (seen > maxBytes) {
        throw Exception(
          'Response too large (over $maxBytes bytes) — refusing to buffer',
        );
      }
      out.add(chunk);
    }
    return utf8.decode(out.takeBytes(), allowMalformed: true);
  }

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
    validateBaseUrl(config.baseUrl);
    final request = await _httpClient.postUrl(config.chatCompletionsUri());
    request.headers.set('Accept-Encoding', 'gzip');
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
      final String errorBody = await readBoundedBody(
        response,
        maxBytes: 64 * 1024,
      );
      debugPrint(
        'RemoteInferenceClient.streamChat failed '
        '(${response.statusCode}): $errorBody',
      );
      throw HttpException(
        'Remote inference failed (${response.statusCode}): '
        '${sanitizeErrorPreview(errorBody)}',
        uri: config.chatCompletionsUri(),
      );
    }

    var buffer = '';
    await for (final chunk in response.transform(utf8.decoder)) {
      buffer += chunk;
      if (buffer.length > maxSseBufferChars) {
        // Misbehaving proxy sending a line-less flood — drop the buffer
        // instead of growing it without bound.
        debugPrint('RemoteInferenceClient: SSE buffer overflow, dropping');
        buffer = '';
        continue;
      }
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
      validateBaseUrl(config.baseUrl);
      final request = await _httpClient.getUrl(config.modelsUri());
      request.headers.set('Accept-Encoding', 'gzip');
      config.headers().forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();

      return response.statusCode >= 200 && response.statusCode < 300;
    } on ArgumentError {
      return false;
    } on Exception {
      return false;
    }
  }

  /// Extracts model ids from an OpenAI-compatible `/models` payload
  /// (`{data: [{id, ...}]}` — Kilo, Zen, OpenRouter, Groq all match).
  /// Pure function so catalog parsing stays unit-testable. Capped at
  /// [maxModelIds] entries; ids longer than [maxModelIdLength] are skipped.
  static List<String> parseModelIds(Object? decoded) {
    if (decoded is! Map<String, Object?>) {
      return const <String>[];
    }
    final Object? data = decoded['data'];
    if (data is! List) {
      return const <String>[];
    }
    final Set<String> ids = <String>{};
    for (final Object? item in data) {
      if (ids.length >= maxModelIds) break;
      if (item is Map<String, Object?>) {
        final Object? id = item['id'];
        if (id is String && id.isNotEmpty && id.length <= maxModelIdLength) {
          ids.add(id);
        }
      }
    }
    final List<String> sorted = ids.toList()..sort();

    return sorted;
  }

  /// Fetches the model catalog (`GET <base>/models`). Throws a
  /// human-readable message on HTTP or parse failures. Bodies are
  /// size-bounded ([maxCatalogBodyBytes]) and error previews sanitized.
  Future<List<String>> fetchModels(RemoteInferenceConfig config) async {
    try {
      validateBaseUrl(config.baseUrl);
    } on ArgumentError catch (e) {
      throw Exception('Invalid remote base URL: ${e.message}');
    }
    final HttpClientRequest request;
    try {
      request = await _httpClient.getUrl(config.modelsUri());
    } on Exception catch (e) {
      throw Exception('Could not reach ${config.modelsUri()}: $e');
    }
    request.headers.set('Accept-Encoding', 'gzip');
    config.headers().forEach(request.headers.set);
    final HttpClientResponse response;
    try {
      response = await request.close().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception('Model list timed out (${config.modelsUri()})');
    }
    late final String body;
    try {
      body = await readBoundedBody(response);
    } on Exception {
      throw Exception(
        'Model list response too large (over $maxCatalogBodyBytes bytes)',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'RemoteInferenceClient.fetchModels failed '
        '(${response.statusCode}): $body',
      );
      throw Exception(
        'Model list failed (${response.statusCode}): '
        '${sanitizeErrorPreview(body)}',
      );
    }
    final List<String> ids;
    try {
      ids = parseModelIds(jsonDecode(body));
    } on FormatException {
      throw Exception('Model list was not valid JSON');
    }
    if (ids.isEmpty) {
      throw Exception('Model list was empty');
    }

    return ids;
  }

  void close() {
    _httpClient.close(force: true);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class WebFetchService {
  static WebFetchService? _instance;
  static WebFetchService get instance => _instance ??= WebFetchService._();
  WebFetchService._();

  static const _defaultMaxLength = 6000;
  static const _minMaxLength = 500;
  static const _maxMaxLength = 12000;
  static const _maxResponseBytes = 2 * 1024 * 1024;
  static const _timeout = Duration(seconds: 15);

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36 NovaAssistant';

  http.Client _client = http.Client();

  @visibleForTesting
  set client(http.Client value) => _client = value;

  @visibleForTesting
  void resetClient() => _client = http.Client();

  Future<Map<String, dynamic>> fetch(Map<String, dynamic> args) async {
    final urlArg = args['url']?.toString().trim() ?? '';
    if (urlArg.isEmpty) {
      return {'success': false, 'error': 'URL is required'};
    }

    final uri = Uri.tryParse(urlArg);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return {
        'success': false,
        'error': 'Only absolute http(s) URLs are supported',
      };
    }

    try {
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = _userAgent
        ..headers['Accept'] =
            'text/html,application/xhtml+xml,text/plain,'
            'application/json;q=0.9,*/*;q=0.5';

      final response = await _client.send(request).timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        unawaited(response.stream.drain<void>());

        return {
          'success': false,
          'error': 'HTTP ${response.statusCode} for $urlArg',
        };
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!_isSupportedContentType(contentType)) {
        unawaited(response.stream.drain<void>());

        return {
          'success': false,
          'error': 'Unsupported content type ($contentType) — not a text page',
        };
      }

      final declaredLength = response.contentLength ?? 0;
      if (declaredLength > _maxResponseBytes) {
        unawaited(response.stream.drain<void>());

        return {'success': false, 'error': _tooLargeMessage(declaredLength)};
      }

      // Stream the body and abort as soon as the byte cap is exceeded so a
      // hostile or huge page cannot balloon memory before the size check.
      final deadline = DateTime.now().add(_timeout);
      final chunks = <int>[];
      var totalBytes = 0;
      try {
        await for (final chunk in response.stream) {
          totalBytes += chunk.length;
          if (totalBytes > _maxResponseBytes) {
            return {'success': false, 'error': _tooLargeMessage(totalBytes)};
          }
          chunks.addAll(chunk);
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('Request timed out');
          }
        }
      } on TimeoutException {
        return {
          'success': false,
          'error': 'Request timed out after 15 seconds',
        };
      }

      if (totalBytes == 0) {
        return {'success': false, 'error': 'No readable text found at $urlArg'};
      }

      final body = _decodeBody(chunks, contentType);
      final isHtml =
          contentType.contains('html') || contentType.contains('xml');
      final text = isHtml ? htmlToPlainText(body) : body.trim();

      final maxLength = _clampMaxLength(args['max_length']);
      var truncated = false;
      var resultText = text;
      if (resultText.length > maxLength) {
        resultText =
            '${resultText.substring(0, maxLength)}\n\n'
            '[Truncated at $maxLength characters — call again with a higher '
            'max_length (up to $_maxMaxLength) to read more]';
        truncated = true;
      }

      if (resultText.trim().isEmpty) {
        return {'success': false, 'error': 'No readable text found at $urlArg'};
      }

      return {
        'success': true,
        'url': uri.toString(),
        'result': resultText,
        if (truncated) 'truncated': true,
      };
    } on TimeoutException {
      return {'success': false, 'error': 'Request timed out after 15 seconds'};
    } on http.ClientException catch (e) {
      return {'success': false, 'error': 'Network error: ${e.message}'};
    } catch (e) {
      debugPrint('WebFetchService.fetch failed: $e');
      return {'success': false, 'error': 'Fetch failed: $e'};
    }
  }

  int _clampMaxLength(Object? raw) {
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (parsed == null) return _defaultMaxLength;
    if (parsed < _minMaxLength) return _minMaxLength;
    if (parsed > _maxMaxLength) return _maxMaxLength;

    return parsed;
  }

  String _tooLargeMessage(int bytes) {
    return 'Page too large (${(bytes / 1048576).toStringAsFixed(1)} MB)';
  }

  /// Decodes response bytes using the charset declared in content-type,
  /// falling back to UTF-8 with malformed-sequence tolerance.
  String _decodeBody(List<int> bytes, String contentType) {
    final match = RegExp(
      'charset=([^\\s;]+)',
      caseSensitive: false,
    ).firstMatch(contentType);
    final name = match?.group(1);
    final isUtf8 =
        name == null ||
        name.toLowerCase() == 'utf-8' ||
        name.toLowerCase() == 'utf8';
    if (isUtf8) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    try {
      return (Encoding.getByName(name) ?? utf8).decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  bool _isSupportedContentType(String contentType) {
    final lowered = contentType.toLowerCase();
    if (lowered.startsWith('text/')) return true;

    return lowered.contains('html') ||
        lowered.contains('xml') ||
        lowered.contains('json');
  }

  /// Converts an HTML document into clean, token-efficient plain text:
  /// strips script/style/head noise, keeps the page title, inserts line
  /// breaks at block-level elements, decodes entities, and collapses runs
  /// of whitespace.
  @visibleForTesting
  static String htmlToPlainText(String html) {
    final document = html_parser.parse(html);
    final title =
        document.querySelector('title')?.text.trim().replaceAll('\n', ' ') ??
        '';

    for (final selector in const [
      'script',
      'style',
      'noscript',
      'svg',
      'head',
      'iframe',
      'form',
      'template',
    ]) {
      document.querySelectorAll(selector).forEach((el) => el.remove());
    }

    final buffer = StringBuffer();
    _extractNodeText(document.documentElement, buffer);

    final lines = buffer
        .toString()
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) return title.isEmpty ? '' : 'Title: $title\n';

    final body = lines.join('\n');

    return title.isEmpty ? body : 'Title: $title\n\n$body';
  }

  static const _blockTags = <String>{
    'address',
    'article',
    'aside',
    'blockquote',
    'br',
    'caption',
    'dd',
    'div',
    'dl',
    'dt',
    'fieldset',
    'figcaption',
    'figure',
    'footer',
    'form',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'li',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
    'ul',
  };

  /// Iterative depth-first text extraction — safe at any nesting depth
  /// (no recursion, so adversarial HTML cannot overflow the stack). Stack
  /// entries are either a node to emit, or `null` — a marker that re-closes
  /// a block element (writes its trailing newline). Children are pushed in
  /// reverse so document order is preserved.
  static void _extractNodeText(dom.Node? root, StringBuffer buffer) {
    if (root == null) return;

    final stack = List<dom.Node?>.from([root]);
    while (stack.isNotEmpty) {
      final node = stack.removeLast();

      if (node == null) {
        buffer.write('\n');

        continue;
      }

      if (node is dom.Text) {
        buffer.write(node.text);

        continue;
      }

      if (node is dom.Element) {
        final tag = node.localName ?? '';
        final isBlock = _blockTags.contains(tag);
        if (isBlock) {
          buffer.write('\n');
          stack.add(null);
        }
        for (final child in node.nodes.toList().reversed) {
          stack.add(child);
        }
      }
    }
  }
}

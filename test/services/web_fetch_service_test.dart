import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_assistant/platform/tool_executor_service.dart';
import 'package:nova_assistant/services/web_fetch_service.dart';

void main() {
  late WebFetchService service;

  setUp(() {
    service = WebFetchService.instance;
    service.resetClient();
  });

  group('WebFetchService.fetch', () {
    test('rejects missing URL', () async {
      final result = await service.fetch({});

      expect(result['success'], false);
      expect(result['error'], 'URL is required');
    });

    test('rejects non-http schemes', () async {
      final result = await service.fetch({'url': 'ftp://example.com/file'});

      expect(result['success'], false);
      expect(result['error'], contains('http(s)'));
    });

    test('rejects URLs without a scheme', () async {
      final result = await service.fetch({'url': 'example.com/page'});

      expect(result['success'], false);
      expect(result['error'], contains('http(s)'));
    });

    test('converts HTML pages to plain text', () async {
      const page = '''
        <html>
          <head><title>Test Page</title><style>.x{color:red}</style></head>
          <body>
            <script>console.log("noise");</script>
            <h1>Hello</h1>
            <p>First &amp; second &lt;line&gt;</p>
            <p>Third line</p>
          </body>
        </html>
      ''';
      service.client = MockClient(
        (_) async => http.Response(
          page,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      );

      final result = await service.fetch({'url': 'https://example.com/a'});

      expect(result['success'], true);
      expect(result['url'], 'https://example.com/a');
      final text = result['result'] as String;
      expect(text, startsWith('Title: Test Page'));
      expect(text, contains('Hello'));
      expect(text, contains('First & second <line>'));
      expect(text, contains('Third line'));
      expect(text, isNot(contains('console.log')));
      expect(text, isNot(contains('color:red')));
    });

    test('returns plain text bodies unchanged', () async {
      service.client = MockClient(
        (_) async => http.Response(
          'plain data',
          200,
          headers: {'content-type': 'text/plain'},
        ),
      );

      final result = await service.fetch({'url': 'https://example.com/t.txt'});

      expect(result['success'], true);
      expect(result['result'], 'plain data');
    });

    test('reports HTTP errors', () async {
      service.client = MockClient((_) async => http.Response('nope', 404));

      final result = await service.fetch({'url': 'https://example.com/404'});

      expect(result['success'], false);
      expect(result['error'], contains('HTTP 404'));
    });

    test('rejects binary content types', () async {
      service.client = MockClient(
        (_) async => http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );

      final result = await service.fetch({'url': 'https://example.com/x.png'});

      expect(result['success'], false);
      expect(result['error'], contains('image/png'));
    });

    test('truncates long content at default length', () async {
      final longBody = 'a' * 9000;
      service.client = MockClient(
        (_) async => http.Response(
          longBody,
          200,
          headers: {'content-type': 'text/plain'},
        ),
      );

      final result = await service.fetch({'url': 'https://example.com/long'});

      expect(result['success'], true);
      expect(result['truncated'], true);
      expect((result['result'] as String).length, lessThan(9000));
      expect(result['result'], contains('[Truncated at 6000 characters'));
    });

    test('clamps max_length arguments', () async {
      final longBody = 'b' * 20000;
      service.client = MockClient(
        (_) async => http.Response(
          longBody,
          200,
          headers: {'content-type': 'text/plain'},
        ),
      );

      final tooHigh = await service.fetch({
        'url': 'https://example.com/long',
        'max_length': 999999,
      });
      expect(tooHigh['success'], true);
      expect(tooHigh['result'], contains('[Truncated at 12000 characters'));

      final tooLow = await service.fetch({
        'url': 'https://example.com/long',
        'max_length': 10,
      });
      expect(tooLow['success'], true);
      expect(tooLow['result'], contains('[Truncated at 500 characters'));

      final asString = await service.fetch({
        'url': 'https://example.com/long',
        'max_length': '7000',
      });
      expect(asString['success'], true);
      expect(asString['result'], contains('[Truncated at 7000 characters'));
    });

    test('maps timeouts to a friendly error', () async {
      service.client = MockClient(
        (_) async => throw TimeoutException('timed out'),
      );

      final result = await service.fetch({'url': 'https://example.com/slow'});

      expect(result['success'], false);
      expect(result['error'], contains('timed out'));
    });

    test('maps client exceptions to a network error', () async {
      service.client = MockClient(
        (_) async => throw http.ClientException('connection refused'),
      );

      final result = await service.fetch({'url': 'https://example.com/dead'});

      expect(result['success'], false);
      expect(result['error'], contains('Network error'));
    });

    test('reports empty readable content', () async {
      service.client = MockClient(
        (_) async =>
            http.Response('', 200, headers: {'content-type': 'text/html'}),
      );

      final result = await service.fetch({'url': 'https://example.com/empty'});

      expect(result['success'], false);
      expect(result['error'], contains('No readable text'));
    });

    test('matches content-type case-insensitively', () async {
      service.client = MockClient(
        (_) async => http.Response(
          '<p>ok</p>',
          200,
          headers: {'content-type': 'TEXT/HTML; CHARSET=UTF-8'},
        ),
      );

      final result = await service.fetch({'url': 'https://example.com/caps'});

      expect(result['success'], true);
      expect(result['result'], contains('ok'));
    });

    test('omits truncated flag when content fits', () async {
      service.client = MockClient(
        (_) async => http.Response(
          'short',
          200,
          headers: {'content-type': 'text/plain'},
        ),
      );

      final result = await service.fetch({'url': 'https://example.com/short'});

      expect(result['success'], true);
      expect(result.containsKey('truncated'), isFalse);
    });

    test('aborts downloads exceeding the byte cap', () async {
      final oversized = 'x' * (2 * 1024 * 1024 + 1024);
      service.client = MockClient(
        (_) async => http.Response(
          oversized,
          200,
          headers: {'content-type': 'text/plain'},
        ),
      );

      final result = await service.fetch({'url': 'https://example.com/huge'});

      expect(result['success'], false);
      expect(result['error'], contains('Page too large'));
    });
  });

  group('WebFetchService.htmlToPlainText', () {
    test('extracts title before dropping head noise', () {
      final text = WebFetchService.htmlToPlainText(
        '<html><head><title>My Site</title></head>'
        '<body><p>Content</p></body></html>',
      );

      expect(text, startsWith('Title: My Site'));
      expect(text, contains('Content'));
    });

    test('strips scripts, styles, and iframes', () {
      final text = WebFetchService.htmlToPlainText(
        '<body><script>evil()</script>'
        '<style>body{}</style>'
        '<iframe src="x"></iframe>'
        '<p>visible</p></body>',
      );

      expect(text, isNot(contains('evil')));
      expect(text, isNot(contains('body{}')));
      expect(text, contains('visible'));
    });

    test('decodes HTML entities', () {
      final text = WebFetchService.htmlToPlainText(
        '<p>Fish &amp; Chips &copy; 2026</p>',
      );

      expect(text, contains('Fish & Chips © 2026'));
    });

    test('breaks lines at block elements and collapses whitespace', () {
      final text = WebFetchService.htmlToPlainText(
        '<div>one   two</div>\n<div>three</div>',
      );

      final lines = text.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, ['one two', 'three']);
    });

    test('returns empty string for documents without text or title', () {
      final text = WebFetchService.htmlToPlainText(
        '<html><body></body></html>',
      );

      expect(text, isEmpty);
    });

    test('survives deeply nested HTML without stack overflow', () {
      const depth = 5000;
      final html =
          '<html><body>${'<div>' * depth}deep${'</div>' * depth}</body></html>';

      expect(WebFetchService.htmlToPlainText(html), contains('deep'));
    });
  });

  group('ToolExecutorService routing', () {
    test("routes 'webfetch' to WebFetchService", () async {
      // Missing URL short-circuits inside WebFetchService before any network
      // or platform-channel call, proving the Dart-side switch handles it.
      final result = await ToolExecutorService.instance.executeTool(
        'webfetch',
        {},
      );

      expect(result['success'], false);
      expect(result['error'], 'URL is required');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/remote_inference_client.dart';

void main() {
  group('RemoteInferenceClient.parseSseData', () {
    test('parses delta content', () {
      expect(
        RemoteInferenceClient.parseSseData(
          'data: {"choices":[{"delta":{"content":"Hi"}}]}',
        ),
        'Hi',
      );
    });

    test('returns null for DONE', () {
      expect(RemoteInferenceClient.parseSseData('data: [DONE]'), isNull);
    });

    test('returns null for empty or non-data lines', () {
      expect(RemoteInferenceClient.parseSseData(''), isNull);
      expect(RemoteInferenceClient.parseSseData(': comment'), isNull);
    });
  });

  group('RemoteInferenceClient.parseModelIds', () {
    test('parses kilo catalog shape', () {
      final ids = RemoteInferenceClient.parseModelIds(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{'id': 'kilo-auto/free'},
          <String, Object?>{'id': 'kilo-auto/efficient'},
          <String, Object?>{'id': ''},
          <String, Object?>{'name': 'no-id'},
        ],
      });

      expect(ids, <String>['kilo-auto/efficient', 'kilo-auto/free']);
    });

    test('parses zen catalog shape', () {
      final ids = RemoteInferenceClient.parseModelIds(<String, Object?>{
        'object': 'list',
        'data': <Object?>[
          <String, Object?>{'id': 'claude-sonnet-4', 'object': 'model'},
          <String, Object?>{'id': 'claude-sonnet-4', 'object': 'model'},
        ],
      });

      expect(ids, <String>['claude-sonnet-4']);
    });

    test('returns empty for garbage payloads', () {
      expect(RemoteInferenceClient.parseModelIds(null), isEmpty);
      expect(RemoteInferenceClient.parseModelIds(<String, Object?>{}), isEmpty);
      expect(
        RemoteInferenceClient.parseModelIds(<String, Object?>{'data': 'x'}),
        isEmpty,
      );
    });

    test('caps oversized catalogs at maxModelIds', () {
      final data = <Object?>[
        for (int i = 0; i < RemoteInferenceClient.maxModelIds + 200; i++)
          <String, Object?>{'id': 'model-$i'},
      ];
      final ids = RemoteInferenceClient.parseModelIds(<String, Object?>{
        'data': data,
      });

      expect(ids, hasLength(RemoteInferenceClient.maxModelIds));
    });

    test('drops ids longer than maxModelIdLength', () {
      final longId = 'x' * (RemoteInferenceClient.maxModelIdLength + 1);
      final ids = RemoteInferenceClient.parseModelIds(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{'id': longId},
          <String, Object?>{'id': 'ok-model'},
        ],
      });

      expect(ids, <String>['ok-model']);
    });
  });

  group('RemoteInferenceClient.validateBaseUrl', () {
    test('accepts http LAN and https cloud URLs', () {
      expect(
        RemoteInferenceClient.validateBaseUrl('http://192.168.1.20:8080')
            .scheme,
        'http',
      );
      expect(
        RemoteInferenceClient.validateBaseUrl(
          'https://api.kilo.ai/api/gateway/',
        ).host,
        'api.kilo.ai',
      );
    });

    test('rejects file:// and other non-http schemes', () {
      expect(
        () => RemoteInferenceClient.validateBaseUrl('file:///etc/passwd'),
        throwsArgumentError,
      );
      expect(
        () => RemoteInferenceClient.validateBaseUrl('ftp://example.com/models'),
        throwsArgumentError,
      );
      expect(
        () => RemoteInferenceClient.validateBaseUrl(''),
        throwsArgumentError,
      );
      expect(
        () => RemoteInferenceClient.validateBaseUrl('not a url'),
        throwsArgumentError,
      );
    });

    test('rejects embedded credentials and missing hosts', () {
      expect(
        () => RemoteInferenceClient.validateBaseUrl(
          'https://user:pass@example.com/v1',
        ),
        throwsArgumentError,
      );
      expect(
        () => RemoteInferenceClient.validateBaseUrl('https://'),
        throwsArgumentError,
      );
    });
  });

  group('RemoteInferenceClient.isPrivateIpHost', () {
    test('flags private IPv4 ranges and localhost', () {
      expect(RemoteInferenceClient.isPrivateIpHost('192.168.1.20'), isTrue);
      expect(RemoteInferenceClient.isPrivateIpHost('10.0.0.1'), isTrue);
      expect(RemoteInferenceClient.isPrivateIpHost('172.16.5.4'), isTrue);
      expect(RemoteInferenceClient.isPrivateIpHost('172.31.255.255'), isTrue);
      expect(RemoteInferenceClient.isPrivateIpHost('127.0.0.1'), isTrue);
      expect(RemoteInferenceClient.isPrivateIpHost('localhost'), isTrue);
      expect(RemoteInferenceClient.isPrivateIpHost('::1'), isTrue);
    });

    test('allows public IPs and public DNS', () {
      expect(RemoteInferenceClient.isPrivateIpHost('8.8.8.8'), isFalse);
      expect(RemoteInferenceClient.isPrivateIpHost('172.32.0.1'), isFalse);
      expect(RemoteInferenceClient.isPrivateIpHost('api.kilo.ai'), isFalse);
    });
  });

  group('RemoteInferenceClient.sanitizeErrorPreview', () {
    test('collapses whitespace and truncates long bodies', () {
      expect(
        RemoteInferenceClient.sanitizeErrorPreview(
          '<html>\n  <body>  Bad   Gateway </body>\n</html>',
        ),
        '<html> <body> Bad Gateway </body> </html>',
      );
      final long = 'x' * 500;
      final preview = RemoteInferenceClient.sanitizeErrorPreview(long);
      expect(preview.length, lessThanOrEqualTo(121));
      expect(preview.endsWith('…'), isTrue);
    });
  });

  group('RemoteInferenceClient.readBoundedBody', () {
    test('reads small bodies', () async {
      final body = await RemoteInferenceClient.readBoundedBody(
        Stream<List<int>>.fromIterable([
          [104, 105],
        ]),
        maxBytes: 10,
      );

      expect(body, 'hi');
    });

    test('refuses oversized catalog bodies', () async {
      await expectLater(
        RemoteInferenceClient.readBoundedBody(
          Stream<List<int>>.fromIterable([
            List<int>.filled(8, 120),
            List<int>.filled(8, 121),
          ]),
          maxBytes: 10,
        ),
        throwsException,
      );
    });
  });
}

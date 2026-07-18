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
}

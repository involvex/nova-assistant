import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    late ChatMessage message;
    late DateTime testTime;

    setUp(() {
      testTime = DateTime(2026, 7, 5, 14, 30);
      message = ChatMessage(
        id: 'test-id-1',
        text: 'Hello, Nova!',
        isUser: true,
        timestamp: testTime,
      );
    });

    test('constructs with required fields only', () {
      expect(message.id, 'test-id-1');
      expect(message.text, 'Hello, Nova!');
      expect(message.isUser, true);
      expect(message.timestamp, testTime);
      expect(message.imageData, isNull);
      expect(message.modelName, isNull);
      expect(message.isStreaming, false);
      expect(message.isError, false);
    });

    test('constructs with all optional fields', () {
      final image = Uint8List.fromList([1, 2, 3]);
      final fullMessage = ChatMessage(
        id: 'full-id',
        text: 'Full message',
        isUser: false,
        timestamp: testTime,
        imageData: image,
        modelName: 'Gemma 4 E2B',
        isStreaming: true,
        isError: true,
      );

      expect(fullMessage.imageData, image);
      expect(fullMessage.modelName, 'Gemma 4 E2B');
      expect(fullMessage.isStreaming, true);
      expect(fullMessage.isError, true);
    });

    group('copyWith', () {
      test('returns identical copy when no arguments provided', () {
        final copy = message.copyWith();
        expect(copy.id, message.id);
        expect(copy.text, message.text);
        expect(copy.isUser, message.isUser);
        expect(copy.timestamp, message.timestamp);
        expect(copy.imageData, message.imageData);
        expect(copy.modelName, message.modelName);
        expect(copy.isStreaming, message.isStreaming);
        expect(copy.isError, message.isError);
      });

      test('overrides specified fields', () {
        final copy = message.copyWith(
          text: 'Updated text',
          isUser: false,
          modelName: 'SmolLM-135M',
        );
        expect(copy.text, 'Updated text');
        expect(copy.isUser, false);
        expect(copy.modelName, 'SmolLM-135M');
        // Unchanged fields
        expect(copy.id, message.id);
        expect(copy.timestamp, message.timestamp);
      });

      test('can set streaming to true', () {
        final copy = message.copyWith(isStreaming: true);
        expect(copy.isStreaming, true);
        expect(message.isStreaming, false); // original unchanged
      });

      test('can set error to true', () {
        final copy = message.copyWith(isError: true, text: 'Error occurred');
        expect(copy.isError, true);
        expect(copy.text, 'Error occurred');
      });

      test('can set imageData', () {
        final image = Uint8List.fromList([4, 5, 6]);
        final copy = message.copyWith(imageData: image);
        expect(copy.imageData, image);
      });

      test('preserves identity of unmodified fields', () {
        final copy = message.copyWith(text: 'New text');
        expect(copy.id, same(message.id));
        expect(copy.timestamp, same(message.timestamp));
      });
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/session_history_reinjection.dart';
import 'package:nova_assistant/utils/message_limits.dart';

void main() {
  group('SessionHistoryReinjection', () {
    test('skips errors streaming and empty', () {
      final input = [
        ChatMessage(
          id: '1',
          text: '',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '2',
          text: 'hi',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
          isStreaming: true,
        ),
        ChatMessage(
          id: '3',
          text: 'boom',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
          isError: true,
        ),
        ChatMessage(
          id: '4',
          text: 'Hello',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '5',
          text: 'Hi there',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 10_000,
      );

      expect(replay.length, 2);
      expect(replay[0].text, 'Hello');
      expect(replay[0].isUser, isTrue);
      expect(replay[1].text, 'Hi there');
      expect(replay[1].isUser, isFalse);
    });

    test('keeps newest turns within token budget', () {
      final input = [
        for (var i = 0; i < 20; i++)
          ChatMessage(
            id: '$i',
            text: 'x' * 400, // ~100 tokens each
            isUser: i.isEven,
            timestamp: DateTime(2026, 1, 1),
          ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 350, // hard cap → at most 3 × ~100
      );

      expect(replay.length, lessThanOrEqualTo(3));
      expect(replay.last.text, input.last.text);
    });

    test('omits single message that alone exceeds maxTokens', () {
      final input = [
        ChatMessage(
          id: '1',
          text: 'x' * 400, // ~100 tokens
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 50,
      );

      expect(replay, isEmpty);
    });

    test('keeps image-only messages for replay', () {
      final input = [
        ChatMessage(
          id: '1',
          text: '',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
          imageData: Uint8List.fromList([1, 2, 3]),
        ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 10_000,
        model: NovaModel.gemma4E2b,
      );

      expect(replay.length, 1);
      expect(replay.first.hasImage, isTrue);
    });

    test('skips cancelled and stop-only turns', () {
      final input = [
        ChatMessage(
          id: '1',
          text: 'search the web',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '2',
          text: 'partial…',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
          wasCancelled: true,
        ),
        ChatMessage(
          id: '3',
          text: '⏹ Stopped',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '4',
          text: 'did I ask you that',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '5',
          text: 'No, you asked about search.',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 10_000,
      );

      expect(replay.length, 3);
      expect(replay[0].text, 'search the web');
      expect(replay[1].text, 'did I ask you that');
      expect(replay[2].text, 'No, you asked about search.');
    });

    test('sanitizes ChatML before reinjection', () {
      final input = [
        ChatMessage(
          id: '1',
          text: 'hi',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '2',
          text: '<|im_start|>assistant Hello there<|im_end|>',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 10_000,
      );

      expect(replay.length, 2);
      expect(replay[1].text.contains('im_start'), isFalse);
      expect(replay[1].text.contains('Hello there'), isTrue);
    });

    test('drops leading orphan assistant after budget trim', () {
      final input = [
        ChatMessage(
          id: 'a',
          text: 'orphan assistant',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: 'u',
          text: 'user turn',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: 'r',
          text: 'reply',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 10_000,
      );

      expect(replay.first.isUser, isTrue);
      expect(replay.first.text, 'user turn');
    });

    test('estimateChatMessageTokens matches MessageLimits ratio for model', () {
      const text = 'hello world this is a test message';
      final defaultEst = SessionHistoryReinjection.estimateChatMessageTokens(
        ChatMessage(
          id: '1',
          text: text,
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      final gemma = SessionHistoryReinjection.estimateChatMessageTokens(
        ChatMessage(
          id: '1',
          text: text,
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        model: NovaModel.gemma4E2b,
      );
      final expected = MessageLimits.estimateRealTokens(
        text,
        model: NovaModel.gemma4E2b,
      );
      expect(gemma, expected);
      // Without an explicit model the helper uses the default ratio
      // (currently Gemma 4). Both should match the same expected value.
      expect(defaultEst, expected);
    });

    test('buildReplayMessages keeps fewer turns for tighter Gemma 4 ratio', () {
      // 6 turns of mixed prose + code. Gemma 4 tokenizes code more
      // aggressively than chars/4, so the same maxTokens should keep fewer
      // turns when model-aware estimation is used.
      final input = <ChatMessage>[];
      for (var i = 0; i < 6; i++) {
        input.add(
          ChatMessage(
            id: '$i',
            text: 'turn ${'x' * 300}; const fn = (a, b) => a + b;',
            isUser: i.isEven,
            timestamp: DateTime(2026, 1, 1),
          ),
        );
      }

      // Budget big enough to fit at least the last user+assistant pair but
      // tight enough that the older turns must be trimmed away.
      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 500,
        model: NovaModel.gemma4E2b,
      );
      expect(replay.length, lessThan(6));
      // With an even-indexed user as the first message, replay always starts
      // on a user turn once leading orphans are dropped.
      expect(replay.first.isUser, isTrue);
    });
  });
}

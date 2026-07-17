import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/services/session_history_reinjection.dart';

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
        maxTokens: 350, // ~3.5 messages
      );

      expect(replay.length, lessThanOrEqualTo(4));
      expect(replay.last.text, input.last.text);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/document_chunker.dart';
import 'package:nova_assistant/services/conversation_summary_service.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';

void main() {
  group('DocumentChunker', () {
    test('returns single chunk for short text', () {
      final chunks = DocumentChunker.chunk('hello world');
      expect(chunks, ['hello world']);
    });

    test('splits long text with overlap', () {
      final text = List.generate(50, (i) => 'Paragraph $i.\n\n').join();
      final chunks = DocumentChunker.chunk(text, maxChunkSize: 80, overlap: 10);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.isNotEmpty), isTrue);
    });

    test('findRelevant prefers matching chunks', () {
      const text = 'Apples are red.\n\nBananas are yellow.\n\nCars need fuel.';
      final relevant = DocumentChunker.findRelevant(
        text,
        'banana fruit yellow',
        maxChunks: 1,
        maxChunkSize: 40,
      );
      expect(relevant, isNotEmpty);
      expect(relevant.first.toLowerCase(), contains('banana'));
    });
  });

  group('ConversationSummaryService', () {
    test('buildExtractiveSummary via maybeUpdate skips short chats', () async {
      final convo = Conversation(
        messages: [
          ChatMessage(
            id: '1',
            text: 'Hi',
            isUser: true,
            timestamp: DateTime(2024),
          ),
        ],
      );
      final summary = await ConversationSummaryService.instance
          .maybeUpdateSummary(convo);
      expect(summary, isNull);
    });
  });
}

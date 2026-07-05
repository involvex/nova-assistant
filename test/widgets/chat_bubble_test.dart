import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/widgets/chat_bubble.dart';

void main() {
  group('ChatBubble', () {
    testWidgets('renders user message with correct alignment', (tester) async {
      final message = ChatMessage(
        id: '1',
        text: 'Hello!',
        isUser: true,
        timestamp: DateTime(2026, 7, 5, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      // User messages should be right-aligned
      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('renders assistant message with correct alignment', (
      tester,
    ) async {
      final message = ChatMessage(
        id: '2',
        text: 'Hi there!',
        isUser: false,
        timestamp: DateTime(2026, 7, 5, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerLeft);
    });

    testWidgets('displays message text', (tester) async {
      final message = ChatMessage(
        id: '3',
        text: 'Test message content',
        isUser: false,
        timestamp: DateTime(2026, 7, 5, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      expect(find.text('Test message content'), findsOneWidget);
    });

    testWidgets('shows model name badge for assistant messages', (
      tester,
    ) async {
      final message = ChatMessage(
        id: '4',
        text: 'Response',
        isUser: false,
        timestamp: DateTime(2026, 7, 5, 14, 30),
        modelName: 'Gemma 4 E2B',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      expect(find.text('Gemma 4 E2B'), findsOneWidget);
    });

    testWidgets('hides model name for user messages', (tester) async {
      final message = ChatMessage(
        id: '5',
        text: 'User query',
        isUser: true,
        timestamp: DateTime(2026, 7, 5, 14, 30),
        modelName: 'Gemma 4 E2B',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      expect(find.text('Gemma 4 E2B'), findsNothing);
    });

    testWidgets('shows streaming indicator when isStreaming', (tester) async {
      final message = ChatMessage(
        id: '6',
        text: 'Typing...',
        isUser: false,
        timestamp: DateTime(2026, 7, 5, 14, 30),
        isStreaming: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Nova is typing...'), findsOneWidget);
    });

    testWidgets('hides streaming indicator when not streaming', (tester) async {
      final message = ChatMessage(
        id: '7',
        text: 'Done!',
        isUser: false,
        timestamp: DateTime(2026, 7, 5, 14, 30),
        isStreaming: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders Image widget when imageData provided', (tester) async {
      final message = ChatMessage(
        id: '8',
        text: 'With screenshot',
        isUser: true,
        timestamp: DateTime(2026, 7, 5, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      // No image widget when imageData is null
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('formats timestamp correctly', (tester) async {
      final message = ChatMessage(
        id: '9',
        text: 'Timed',
        isUser: false,
        timestamp: DateTime(2026, 7, 5, 9, 5),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('renders markdown in message text', (tester) async {
      final message = ChatMessage(
        id: '10',
        text: '**Bold text** and _italic_',
        isUser: false,
        timestamp: DateTime(2026, 7, 5, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
        ),
      );

      // MarkdownBody should be present
      expect(find.byType(MarkdownBody), findsOneWidget);
    });
  });
}

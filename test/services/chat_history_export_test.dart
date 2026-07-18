import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ChatHistoryService.clear();
  });

  test('exportAsText returns content without writing a file path', () async {
    final convo = Conversation(
      id: 'c1',
      title: 'Test chat',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      messages: [
        ChatMessage(
          id: 'm1',
          text: 'Hello',
          isUser: true,
          timestamp: DateTime(2026, 1, 1, 12),
        ),
      ],
    );
    await ChatHistoryService.saveConversations([convo]);

    final content = await ChatHistoryService.exportAsText();
    expect(content, isNotNull);
    expect(content!, contains('Hello'));
    expect(content, contains('Nova Assistant'));
    expect(content.contains('/data/user/'), isFalse);
    expect(content.endsWith('.txt'), isFalse);
  });
}

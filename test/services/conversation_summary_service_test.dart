import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/services/conversation_summary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
  });

  test('compactNow returns summary and keeps recent turns', () async {
    final messages = [
      for (var i = 0; i < 12; i++)
        ChatMessage(
          id: '$i',
          text: i.isEven ? 'User goal $i about travel' : 'Assistant reply $i',
          isUser: i.isEven,
          timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
    ];
    final conversation = Conversation(
      id: 'c1',
      title: 'Test',
      messages: messages,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final result = await ConversationSummaryService.instance.compactNow(
      conversation,
      keepRecent: 4,
    );

    expect(result.summary, isNotEmpty);
    expect(result.retainedMessages.length, lessThan(messages.length));
    expect(result.retainedMessages.last.text, messages.last.text);
  });
}

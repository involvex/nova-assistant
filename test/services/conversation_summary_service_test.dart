import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/services/conversation_summary_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp('nova_summary_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
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

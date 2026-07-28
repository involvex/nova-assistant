import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
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

ChatMessage _msg(String id, String text, {bool isUser = true}) {
  return ChatMessage(
    id: id,
    text: text,
    isUser: isUser,
    timestamp: DateTime(2026, 1, 1, 12),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('nova_chat_branch_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await ChatHistoryService.clear();
  });

  tearDown(() async {
    await ChatHistoryService.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('branchFromMessage copies prefix and leaves source unchanged', () async {
    final source = Conversation(
      id: 'src',
      title: 'Trip plans',
      messages: [
        _msg('1', 'A'),
        _msg('2', 'B', isUser: false),
        _msg('3', 'C'),
        _msg('4', 'D', isUser: false),
        _msg('5', 'E'),
      ],
    );
    await ChatHistoryService.saveConversations([source]);

    final branched = await ChatHistoryService.branchFromMessage('src', 2);
    expect(branched, isNotNull);
    expect(branched!.id, isNot('src'));
    expect(branched.title, contains('(branch)'));
    expect(branched.messages, hasLength(3));
    expect(branched.messages.map((m) => m.text).toList(), ['A', 'B', 'C']);

    final reloaded = await ChatHistoryService.getConversation('src');
    expect(reloaded, isNotNull);
    expect(reloaded!.messages, hasLength(5));
    expect(reloaded.messages.map((m) => m.text).toList(), [
      'A',
      'B',
      'C',
      'D',
      'E',
    ]);

    final all = await ChatHistoryService.loadConversations();
    expect(all.first.id, branched.id);
    expect(all.any((c) => c.id == 'src'), isTrue);
  });

  test('branchFromMessage returns null for out-of-range index', () async {
    final source = Conversation(id: 'src2', messages: [_msg('1', 'only')]);
    await ChatHistoryService.saveConversations([source]);

    expect(await ChatHistoryService.branchFromMessage('src2', -1), isNull);
    expect(await ChatHistoryService.branchFromMessage('src2', 1), isNull);
    expect(await ChatHistoryService.branchFromMessage('missing', 0), isNull);
  });

  test('branchFromMessage deep-copies messages', () async {
    final source = Conversation(
      id: 'src3',
      messages: [
        ChatMessage(
          id: '1',
          text: 'hello',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
          reactions: {'👍': 1},
        ),
      ],
    );
    await ChatHistoryService.saveConversations([source]);

    final branched = await ChatHistoryService.branchFromMessage('src3', 0);
    expect(branched, isNotNull);
    expect(branched!.messages.single.reactions['👍'], 1);

    branched.messages.single.reactions['👍'] = 99;
    final reloaded = await ChatHistoryService.getConversation('src3');
    expect(reloaded!.messages.single.reactions['👍'], 1);
  });
}

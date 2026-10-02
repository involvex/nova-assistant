import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('nova_chat_delete_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await ChatHistoryService.clear();
  });

  tearDown(() async {
    await ChatHistoryService.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('deleteConversation broadcasts the deleted id', () async {
    final Conversation created = await ChatHistoryService.createConversation();
    final Future<String> first =
        ChatHistoryService.conversationDeletedStream.first;

    await ChatHistoryService.deleteConversation(created.id);

    expect(await first, created.id);
    expect(await ChatHistoryService.getConversation(created.id), isNull);
  });

  test('deleteConversation of unknown id still notifies', () async {
    final Future<String> first =
        ChatHistoryService.conversationDeletedStream.first;

    await ChatHistoryService.deleteConversation('missing-id');

    expect(await first, 'missing-id');
  });
}

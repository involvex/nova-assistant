import 'dart:io';
import 'dart:typed_data';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('nova_chat_hist_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await ChatHistoryService.clear();
  });

  tearDown(() async {
    await ChatHistoryService.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists conversations to a file, not SharedPreferences', () async {
    final convo = Conversation(
      id: 'c1',
      title: 'Test',
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

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('conversations'), isNull);

    final file = File('${tempDir.path}/conversations.json');
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), contains('Hello'));

    final loaded = await ChatHistoryService.loadConversations();
    expect(loaded, hasLength(1));
    expect(loaded.first.messages.first.text, 'Hello');
  });

  test('does not persist screenshot bytes', () async {
    final convo = Conversation(
      id: 'c2',
      messages: [
        ChatMessage(
          id: 'm2',
          text: '',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
          imageData: Uint8List(1024)..fillRange(0, 1024, 7),
        ),
      ],
    );
    await ChatHistoryService.saveConversations([convo]);

    final file = File('${tempDir.path}/conversations.json');
    final raw = await file.readAsString();
    expect(raw, contains('"imageData":null'));
    expect(raw, contains('[Screenshot]'));
    expect(raw.length, lessThan(2000));
  });

  test('appendMessage persists messages and triggers debounced save', () async {
    ChatHistoryService.reset();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();

    final convo = Conversation(
      id: 'debounce',
      title: 'Debounce Test',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await ChatHistoryService.saveConversations([convo]);

    await ChatHistoryService.appendMessage(
      'debounce',
      ChatMessage(
        id: 'm1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );
    await ChatHistoryService.appendMessage(
      'debounce',
      ChatMessage(
        id: 'm2',
        text: 'World',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));

    final loaded = await ChatHistoryService.getConversation('debounce');
    expect(loaded, isNotNull);
    expect(loaded!.messages, hasLength(2));
    expect(loaded.messages[0].text, 'Hello');
    expect(loaded.messages[1].text, 'World');
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/chat_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  late File historyFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nova_history_hydrate');
    historyFile = File('${tempDir.path}/conversations.json');
    ChatHistoryService.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    ChatHistoryService.reset();
    tempDir.deleteSync(recursive: true);
  });

  test('loadConversations restores imageData from imageFile paths', () async {
    final pngBytes = Uint8List.fromList([9, 9, 7, 7, 1]);
    final imageDir = Directory('${tempDir.path}/generated_images');
    await imageDir.create(recursive: true);
    await File('${imageDir.path}/gen-1.png').writeAsBytes(pngBytes);

    const timestamp = '2026-08-22T10:00:00.000';
    historyFile.writeAsStringSync(
      jsonEncode([
        {
          'id': 'conv-1',
          'title': 'Image chat',
          'messages': [
            {
              'id': 'm1',
              'text': 'Generated image for "a cat"',
              'isUser': false,
              'timestamp': timestamp,
              'imageData': null,
              'imageFile': 'generated_images/gen-1.png',
              'modelName': 'Diffusion',
            },
            {
              'id': 'm2',
              'text': 'plain message',
              'isUser': true,
              'timestamp': timestamp,
            },
          ],
          'createdAt': timestamp,
          'updatedAt': timestamp,
        },
      ]),
    );

    final conversations = await ChatHistoryService.loadConversations();

    expect(conversations, hasLength(1));
    final messages = conversations.first.messages;
    expect(messages.first.imageData, pngBytes);
    expect(messages.first.imagePath, 'generated_images/gen-1.png');
    expect(messages.last.imageData, isNull);
  });

  test('missing files degrade gracefully to bytes-free messages', () async {
    const timestamp = '2026-08-22T10:00:00.000';
    historyFile.writeAsStringSync(
      jsonEncode([
        {
          'id': 'conv-1',
          'title': 'Lost image',
          'messages': [
            {
              'id': 'm1',
              'text': 'Generated image for "gone"',
              'isUser': false,
              'timestamp': timestamp,
              'imageFile': 'generated_images/deleted.png',
            },
          ],
          'createdAt': timestamp,
          'updatedAt': timestamp,
        },
      ]),
    );

    final conversations = await ChatHistoryService.loadConversations();

    expect(conversations.first.messages.first.imageData, isNull);
    expect(
      conversations.first.messages.first.imagePath,
      'generated_images/deleted.png',
    );
  });
}

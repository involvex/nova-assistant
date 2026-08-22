import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/generated_image_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nova_gen_img');
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
    tempDir.deleteSync(recursive: true);
  });

  group('GeneratedImageStore', () {
    test('save returns a relative path inside generated_images', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final path = await GeneratedImageStore.instance.save(bytes);

      expect(path, startsWith('generated_images/'));
      expect(path, endsWith('.png'));
    });

    test('saved bytes round-trip through read', () async {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i));
      final path = await GeneratedImageStore.instance.save(bytes);

      final restored = await GeneratedImageStore.instance.read(path);

      expect(restored, isNotNull);
      expect(restored, bytes);
    });

    test('read returns null for missing files', () async {
      final restored = await GeneratedImageStore.instance.read(
        'generated_images/does-not-exist.png',
      );

      expect(restored, isNull);
    });

    test('looksLikeStoredImage rejects paths outside the store', () {
      expect(
        GeneratedImageStore.looksLikeStoredImage('generated_images/a.png'),
        isTrue,
      );
      expect(GeneratedImageStore.looksLikeStoredImage('other/a.png'), isFalse);
      expect(
        GeneratedImageStore.looksLikeStoredImage('generated_images/../x'),
        isFalse,
      );
      expect(GeneratedImageStore.looksLikeStoredImage(null), isFalse);
    });
  });
}

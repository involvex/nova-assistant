import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/uncensored_model_catalog.dart';
import 'package:nova_assistant/services/model_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nova_hash_verify');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name');

    return file..writeAsBytesSync(bytes);
  }

  group('ModelManager.verifyModelHash curated pins', () {
    test('unknown filenames are not blocked', () async {
      final file = writeFile('totally-unknown.litertlm', [1, 2, 3]);
      final ok = await ModelManager.verifyModelHash(
        file.path,
        'totally-unknown.litertlm',
      );

      expect(ok, isTrue);
    });

    test('curated file with wrong digest is rejected', () async {
      const name = 'gemma4_uncensored_INT4_8192.litertlm';
      expect(UncensoredModelCatalog.expectedSha256For(name), isNotNull);

      final file = writeFile(name, List<int>.filled(64, 0xAB));
      final ok = await ModelManager.verifyModelHash(file.path, name);

      expect(ok, isFalse);
    });
  });
}

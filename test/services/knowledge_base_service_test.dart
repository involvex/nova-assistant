import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/services/knowledge_base_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    KnowledgeBaseService.reset();
    SharedPreferences.setMockInitialValues({'settings_knowledge_base': true});
    await SharedPreferences.getInstance();
  });

  group('KnowledgeBaseService chunk token cache', () {
    test('retrieveContext returns relevant chunks after ingest', () async {
      final service = KnowledgeBaseService.instance;
      final tempDir = Directory.systemTemp.createTempSync();
      final file = File('${tempDir.path}/kb_test.txt');
      file.writeAsStringSync(
        'Flutter is a UI toolkit. Dart is the programming language. '
        'Semantic search uses TF-IDF scoring for retrieval.',
      );

      final doc = await service.ingestFile(
        filePath: file.path,
        fileName: 'kb_test.txt',
      );

      expect(doc, isNotNull);

      final result = await service.retrieveContext('semantic search TF-IDF');
      expect(result, isNotNull);
      expect(result, contains('kb_test.txt'));
    });

    test('deleteDocument removes chunks from retrieval', () async {
      final service = KnowledgeBaseService.instance;
      final tempDir = Directory.systemTemp.createTempSync();

      final fileA = File('${tempDir.path}/kb_a.txt');
      fileA.writeAsStringSync('apple banana cherry date');

      final docA = await service.ingestFile(
        filePath: fileA.path,
        fileName: 'kb_a.txt',
      );
      expect(docA, isNotNull);

      var result = await service.retrieveContext('apple');
      expect(result, isNotNull);
      expect(result, contains('kb_a.txt'));

      await service.deleteDocument(docA!.id);

      result = await service.retrieveContext('apple');
      expect(result, isNull);
    });

    test('clear removes all documents and chunks', () async {
      final service = KnowledgeBaseService.instance;
      final tempDir = Directory.systemTemp.createTempSync();
      final file = File('${tempDir.path}/kb_clear.txt');
      file.writeAsStringSync('clear all the things');

      await service.ingestFile(filePath: file.path, fileName: 'kb_clear.txt');
      expect(await service.listDocuments(), isNotEmpty);

      await service.clear();

      expect(await service.listDocuments(), isEmpty);
      expect(await service.retrieveContext('things'), isNull);
    });

    test(
      'retrieveContext falls back to tokenize when cache is empty',
      () async {
        KnowledgeBaseService.reset();
        SharedPreferences.setMockInitialValues({
          'settings_knowledge_base': true,
          'knowledge_base_documents': '[{"id":"doc1","name":"fallback.txt","filePath":"/tmp/fallback.txt","fullText":"hello world","chunks":["hello world"],"createdAt":"2026-01-01T00:00:00.000","charCount":11}]',
        });
        await SharedPreferences.getInstance();

        final service = KnowledgeBaseService.instance;
        final result = await service.retrieveContext('hello');
        expect(result, isNotNull);
        expect(result, contains('fallback.txt'));
      },
    );
  });
}

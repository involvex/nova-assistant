import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/memory/memory_service_v2.dart';
import 'package:nova_assistant/memory/persistent_memory.dart';
import 'package:nova_assistant/memory/session_memory.dart';

void main() {
  group('MemoryServiceV2', () {
    test('session write/read/recent', () async {
      final MemoryServiceV2 memory = MemoryServiceV2();

      await memory.session.write('task', 'APK analysieren');
      expect(await memory.session.read('task'), 'APK analysieren');
      expect((await memory.session.recent()).length, 1);
    });

    test('persistent save/search', () async {
      final MemoryServiceV2 memory = MemoryServiceV2();

      await memory.persistent.save('editor', 'Nutzer mag Dark Mode');
      final List<dynamic> hits = await memory.persistent.search('dark');

      expect(hits.length, 1);
    });

    test('importLegacy migrates without crash', () async {
      final MemoryServiceV2 memory = MemoryServiceV2();

      await memory.importLegacy(
        conversationEntries: <Map<String, String>>[
          <String, String>{'query': 'hi', 'response': 'hallo'},
        ],
        customMemories: <Map<String, Object?>>[
          <String, Object?>{'title': 'lang', 'content': 'Deutsch'},
        ],
      );

      expect(await memory.persistent.load('lang'), 'Deutsch');
    });

    test('buildContext merges persistent + session', () async {
      final MemoryServiceV2 memory = MemoryServiceV2(
        session: InMemorySessionMemory(),
        persistent: InMemoryPersistentMemory(),
      );

      await memory.persistent.save('modell', 'Bevorzugt Qwen lokal');
      await memory.session.write('task', 'Analyse läuft');

      final String? context = await memory.buildContext('modell');

      expect(context, isNotNull);
      expect(context!, contains('Qwen'));
    });

    test('buildContext null when empty', () async {
      final MemoryServiceV2 memory = MemoryServiceV2();

      expect(await memory.buildContext('xyz'), isNull);
    });
  });
}

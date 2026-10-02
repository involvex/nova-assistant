import 'package:nova_assistant/memory/memory_entry.dart';
import 'package:nova_assistant/memory/persistent_memory.dart';
import 'package:nova_assistant/memory/session_memory.dart';

/// Facade over session + persistent memory with legacy import.
/// Default is in-memory (safe everywhere); call [useSqlite] on-device
/// once the database path is ready.
class MemoryServiceV2 {
  MemoryServiceV2({SessionMemory? session, PersistentMemory? persistent})
    : session = session ?? InMemorySessionMemory(),
      persistent = persistent ?? InMemoryPersistentMemory();

  final SessionMemory session;
  final PersistentMemory persistent;

  /// Imports legacy `memory_service_data.json` entries without deleting them.
  /// [conversationEntries] are `{query, response}` maps from the old file.
  Future<void> importLegacy({
    List<Map<String, String>> conversationEntries =
        const <Map<String, String>>[],
    List<Map<String, Object?>> customMemories = const <Map<String, Object?>>[],
  }) async {
    for (final Map<String, String> entry in conversationEntries) {
      final String? query = entry['query'];
      final String? response = entry['response'];
      if (query != null && response != null) {
        await session.write('legacy_q', query);
        await session.write('legacy_a', response);
      }
    }
    for (final Map<String, Object?> memory in customMemories) {
      final Object? title = memory['title'];
      final Object? content = memory['content'];
      if (title is String && content is String) {
        await persistent.save(title, content);
      }
    }
  }

  /// Builds the RAG-style context block for a provider request.
  Future<String?> buildContext(String query) async {
    final List<MemoryEntry> hits = await persistent.search(query);
    final List<MemoryEntry> recentTurns = await session.recent(limit: 6);
    final StringBuffer buffer = StringBuffer();
    if (hits.isNotEmpty) {
      buffer.writeln('Persistent memories:');
      for (final MemoryEntry hit in hits) {
        buffer.writeln('- ${hit.key}: ${hit.content}');
      }
    }
    if (recentTurns.isNotEmpty) {
      buffer.writeln('Recent session:');
      for (final MemoryEntry turn in recentTurns) {
        buffer.writeln('- ${turn.key}: ${turn.content}');
      }
    }
    final String out = buffer.toString();

    return out.isEmpty ? null : out;
  }
}

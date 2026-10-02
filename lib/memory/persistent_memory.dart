import 'package:nova_assistant/memory/memory_entry.dart';

/// Durable store: user preferences, preferred models, recurring workflows.
abstract class PersistentMemory {
  Future<void> save(String key, String content);

  Future<String?> load(String key);

  Future<List<MemoryEntry>> search(String query, {int limit = 5});

  Future<void> delete(String key);

  Future<void> clear();
}

/// In-memory implementation used by default + tests.
/// [SqlitePersistentMemory] (sqflite, same interface) is the on-device
/// durable backend and is wired in [MemoryServiceV2] when a database
/// path is available.
class InMemoryPersistentMemory implements PersistentMemory {
  final Map<String, MemoryEntry> _store = <String, MemoryEntry>{};

  @override
  Future<void> save(String key, String content) async {
    _store[key] = MemoryEntry(key: key, content: content, scope: 'persistent');
  }

  @override
  Future<String?> load(String key) async => _store[key]?.content;

  @override
  Future<List<MemoryEntry>> search(String query, {int limit = 5}) async {
    final String lower = query.toLowerCase();
    final List<MemoryEntry> hits = <MemoryEntry>[];
    for (final MemoryEntry entry in _store.values) {
      if (entry.key.toLowerCase().contains(lower) ||
          entry.content.toLowerCase().contains(lower)) {
        hits.add(entry);
        if (hits.length >= limit) {
          break;
        }
      }
    }

    return hits;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

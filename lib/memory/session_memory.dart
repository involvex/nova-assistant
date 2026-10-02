import 'package:nova_assistant/memory/memory_entry.dart';

/// Ephemeral per-conversation state: current task, active app, turn history.
abstract class SessionMemory {
  Future<void> write(String key, String content);

  Future<String?> read(String key);

  Future<List<MemoryEntry>> recent({int limit = 20});

  Future<void> clear();
}

/// In-memory implementation (default; SQLite lands in [SqliteSessionMemory]).
class InMemorySessionMemory implements SessionMemory {
  final List<MemoryEntry> _entries = <MemoryEntry>[];

  @override
  Future<void> write(String key, String content) async {
    _entries.add(MemoryEntry(key: key, content: content, scope: 'session'));
  }

  @override
  Future<String?> read(String key) async {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (_entries[i].key == key) {
        return _entries[i].content;
      }
    }

    return null;
  }

  @override
  Future<List<MemoryEntry>> recent({int limit = 20}) async {
    final int start = _entries.length - limit < 0 ? 0 : _entries.length - limit;

    return List<MemoryEntry>.unmodifiable(_entries.sublist(start));
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}

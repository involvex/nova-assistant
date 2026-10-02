import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:nova_assistant/memory/memory_entry.dart';
import 'package:nova_assistant/memory/persistent_memory.dart';
import 'package:nova_assistant/memory/session_memory.dart';

/// Shared database file for both memory stores. Creating both tables in one
/// `onCreate` avoids the "second opener misses its table" race.
Future<Database> openNovaMemoryDb() async {
  final String dir = (await getApplicationDocumentsDirectory()).path;
  final String path = p.join(dir, 'nova_memory.db');

  return openDatabase(
    path,
    version: 1,
    onCreate: (Database db, int version) async {
      await db.execute(
        'CREATE TABLE memories('
        'key TEXT PRIMARY KEY, content TEXT NOT NULL, '
        'scope TEXT NOT NULL, created_at TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE session_entries('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT NOT NULL, '
        'content TEXT NOT NULL, created_at TEXT NOT NULL)',
      );
    },
  );
}

/// sqflite-backed [PersistentMemory]. Lazy-opened; callers keep the in-memory
/// default until the database is ready, so tests never touch native code.
class SqlitePersistentMemory implements PersistentMemory {
  SqlitePersistentMemory({Database? databaseForTesting})
    : _testDb = databaseForTesting;

  Database? _db;
  final Database? _testDb;

  static const String table = 'memories';

  Future<Database> _open() async {
    final Database? testDb = _testDb;
    if (testDb != null) {
      return testDb;
    }
    final Database? opened = _db;
    if (opened != null) {
      return opened;
    }
    _db = await openNovaMemoryDb();

    return _db!;
  }

  @override
  Future<void> save(String key, String content) async {
    final Database db = await _open();
    await db.insert(table, <String, Object?>{
      'key': key,
      'content': content,
      'scope': 'persistent',
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String?> load(String key) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final Object? content = rows.first['content'];

    return content is String ? content : null;
  }

  @override
  Future<List<MemoryEntry>> search(String query, {int limit = 5}) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: 'key LIKE ? OR content LIKE ?',
      whereArgs: <Object?>['%$query%', '%$query%'],
      limit: limit,
    );
    final List<MemoryEntry> out = <MemoryEntry>[];
    for (final Map<String, Object?> row in rows) {
      final Object? key = row['key'];
      final Object? content = row['content'];
      if (key is String && content is String) {
        out.add(MemoryEntry(key: key, content: content, scope: 'persistent'));
      }
    }

    return out;
  }

  @override
  Future<void> delete(String key) async {
    final Database db = await _open();
    await db.delete(table, where: 'key = ?', whereArgs: <Object?>[key]);
  }

  @override
  Future<void> clear() async {
    final Database db = await _open();
    await db.delete(table);
  }
}

/// sqflite-backed [SessionMemory] sharing the same database file.
class SqliteSessionMemory implements SessionMemory {
  SqliteSessionMemory({Database? databaseForTesting})
    : _testDb = databaseForTesting;

  Database? _db;
  final Database? _testDb;

  static const String table = 'session_entries';

  Future<Database> _open() async {
    final Database? testDb = _testDb;
    if (testDb != null) {
      return testDb;
    }
    final Database? opened = _db;
    if (opened != null) {
      return opened;
    }
    _db = await openNovaMemoryDb();

    return _db!;
  }

  @override
  Future<void> write(String key, String content) async {
    final Database db = await _open();
    await db.insert(table, <String, Object?>{
      'key': key,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<String?> read(String key) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: 'key = ?',
      whereArgs: <Object?>[key],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final Object? content = rows.first['content'];

    return content is String ? content : null;
  }

  @override
  Future<List<MemoryEntry>> recent({int limit = 20}) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.query(
      table,
      orderBy: 'id DESC',
      limit: limit,
    );
    final List<MemoryEntry> out = <MemoryEntry>[];
    for (final Map<String, Object?> row in rows.reversed) {
      final Object? key = row['key'];
      final Object? content = row['content'];
      if (key is String && content is String) {
        out.add(MemoryEntry(key: key, content: content));
      }
    }

    return out;
  }

  @override
  Future<void> clear() async {
    final Database db = await _open();
    await db.delete(table);
  }
}

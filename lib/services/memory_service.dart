import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryService {
  static const _key = 'rag_conversations';
  static const _customMemoriesKey = 'custom_memories';
  static SharedPreferences? _prefs;
  static const _maxEntries = 50;
  static const _maxEntryLength = 1000;

  static Future<void> initialize() async {}

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<void> storeConversation(String query, String response) async {
    final isEnabled = await _isConversationMemoryEnabled();
    if (!isEnabled) return;

    try {
      final p = await _p;
      final existing = p.getString(_key);
      final List<Map<String, String>> entries = existing != null
          ? List<Map<String, String>>.from(
              (jsonDecode(existing) as List<dynamic>).map(
                (e) => Map<String, String>.from(e as Map),
              ),
            )
          : [];

      final truncatedQuery = query.length > _maxEntryLength
          ? query.substring(0, _maxEntryLength)
          : query;
      final truncatedResponse = response.length > _maxEntryLength
          ? response.substring(0, _maxEntryLength)
          : response;

      entries.add({
        'query': truncatedQuery,
        'response': truncatedResponse,
        'time': DateTime.now().toIso8601String(),
      });

      if (entries.length > _maxEntries) {
        entries.removeRange(0, entries.length - _maxEntries);
      }

      await p.setString(_key, jsonEncode(entries));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getCustomMemories() async {
    try {
      final p = await _p;
      final existing = p.getString(_customMemoriesKey);
      if (existing == null) return [];
      return (jsonDecode(existing) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addCustomMemory(String title, String content) async {
    try {
      final p = await _p;
      final existing = p.getString(_customMemoriesKey);
      final List<Map<String, dynamic>> memories = existing != null
          ? (jsonDecode(existing) as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : [];

      memories.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': title,
        'content': content,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await p.setString(_customMemoriesKey, jsonEncode(memories));
    } catch (_) {}
  }

  static Future<void> updateCustomMemory(
    String id,
    String title,
    String content,
  ) async {
    try {
      final p = await _p;
      final existing = p.getString(_customMemoriesKey);
      if (existing == null) return;

      final memories = (jsonDecode(existing) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final index = memories.indexWhere((m) => m['id'] == id);
      if (index != -1) {
        memories[index] = {
          ...memories[index],
          'title': title,
          'content': content,
        };
        await p.setString(_customMemoriesKey, jsonEncode(memories));
      }
    } catch (_) {}
  }

  static Future<void> deleteCustomMemory(String id) async {
    try {
      final p = await _p;
      final existing = p.getString(_customMemoriesKey);
      if (existing == null) return;

      final memories = (jsonDecode(existing) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      memories.removeWhere((m) => m['id'] == id);
      await p.setString(_customMemoriesKey, jsonEncode(memories));
    } catch (_) {}
  }

  static Future<String?> retrieveContext(String query) async {
    final buffer = StringBuffer();

    final customContext = await retrieveCustomMemoriesContext(query);
    if (customContext != null) {
      buffer.write(customContext);
    }

    final conversationContext = await _retrieveConversationContext(query);
    if (conversationContext != null) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(conversationContext);
    }

    return buffer.isEmpty ? null : buffer.toString();
  }

  static Future<String?> retrieveCustomMemoriesContext(String query) async {
    final isEnabled = await _isCustomMemoryEnabled();
    if (!isEnabled) return null;

    try {
      final memories = await getCustomMemories();
      if (memories.isEmpty) return null;

      final queryLower = query.toLowerCase();
      final relevant = memories.where((m) {
        final text = '${m['title']} ${m['content']}'.toLowerCase();
        return queryLower
            .split(' ')
            .any((word) => word.isNotEmpty && text.contains(word));
      }).toList();

      if (relevant.isEmpty) return null;

      final buf = StringBuffer('Custom memories:\n');
      for (final m in relevant) {
        buf.writeln('- ${m['title']}: ${m['content']}');
      }
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _retrieveConversationContext(String query) async {
    final isEnabled = await _isConversationMemoryEnabled();
    if (!isEnabled) return null;

    try {
      final p = await _p;
      final existing = p.getString(_key);
      if (existing == null) return null;

      final entries = (jsonDecode(existing) as List<dynamic>)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();

      if (entries.isEmpty) return null;

      final queryWords = query.toLowerCase().split(RegExp(r'\s+')).toSet();

      final scored = entries.map((e) {
        final text = '${e['query']} ${e['response']}'.toLowerCase();
        final words = text.split(RegExp(r'\s+')).toSet();
        final overlap = queryWords.intersection(words).length;
        final normalized =
            queryWords.isEmpty ? 0.0 : overlap / queryWords.length;

        final ageInDays = DateTime.now()
            .difference(DateTime.parse(e['time'] as String))
            .inDays;
        final recencyBonus =
            ageInDays == 0 ? 2.0 : 1.0 / (1.0 + ageInDays * 0.1);

        return MapEntry(e, normalized + recencyBonus);
      }).toList();

      scored.sort((a, b) => b.value.compareTo(a.value));
      final top = scored.take(3).where((s) => s.value > 0.5).toList();

      if (top.isEmpty) return null;

      final buf = StringBuffer('Relevant past conversation:\n');
      for (final entry in top) {
        buf.writeln('- Q: ${entry.key['query']}');
        buf.writeln('  A: ${entry.key['response']}');
      }
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isConversationMemoryEnabled() async {
    final p = await _p;
    return p.getBool('settings_rag_memory') ?? false;
  }

  static Future<bool> _isCustomMemoryEnabled() async {
    final p = await _p;
    return p.getBool('settings_custom_memory') ?? true;
  }

  static Future<void> clearConversationHistory() async {
    try {
      final p = await _p;
      await p.remove(_key);
    } catch (_) {}
  }

  static Future<void> clearCustomMemories() async {
    try {
      final p = await _p;
      await p.remove(_customMemoriesKey);
    } catch (_) {}
  }

  static Future<void> clear() async {
    await clearConversationHistory();
    await clearCustomMemories();
  }
}

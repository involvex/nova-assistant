import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryService {
  static const _key = 'rag_conversations';
  static SharedPreferences? _prefs;
  static const _maxEntries = 50;

  static Future<void> initialize() async {}

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<void> storeConversation(String query, String response) async {
    final isEnabled = await _isEnabled();
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

      entries.add({
        'query': query,
        'response': response,
        'time': DateTime.now().toIso8601String(),
      });

      if (entries.length > _maxEntries) {
        entries.removeRange(0, entries.length - _maxEntries);
      }

      await p.setString(_key, jsonEncode(entries));
    } catch (_) {}
  }

  static Future<String?> retrieveContext(String query) async {
    final isEnabled = await _isEnabled();
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

      // Score entries by keyword overlap with query
      final scored = entries.map((e) {
        final text = '${e['query']} ${e['response']}'.toLowerCase();
        final words = text.split(RegExp(r'\s+')).toSet();
        final overlap = queryWords.intersection(words).length;
        return MapEntry(e, overlap);
      }).toList();

      // Get top 3 by score
      scored.sort((a, b) => b.value.compareTo(a.value));
      final top = scored.take(3).where((s) => s.value > 0).toList();

      if (top.isEmpty) return null;

      final buffer = StringBuffer('Relevant past conversation:\n');
      for (final entry in top) {
        buffer.writeln('- Q: ${entry.key['query']}');
        buffer.writeln('  A: ${entry.key['response']}');
      }
      return buffer.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isEnabled() async {
    final p = await _p;
    return p.getBool('settings_rag_memory') ?? false;
  }

  static Future<void> clear() async {
    try {
      final p = await _p;
      await p.remove(_key);
    } catch (_) {}
  }
}

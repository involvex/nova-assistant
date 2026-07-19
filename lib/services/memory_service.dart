import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/services/knowledge_base_service.dart';
import 'package:nova_assistant/services/semantic_search.dart';

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
    } catch (e) {
      debugPrint('MemoryService.storeConversation error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getCustomMemories() async {
    try {
      final p = await _p;
      final existing = p.getString(_customMemoriesKey);
      if (existing == null) return [];
      return (jsonDecode(existing) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('MemoryService.getCustomMemories error: $e');
      return [];
    }
  }

  static Future<void> addCustomMemory(
    String title,
    String content, {
    String source = 'manual',
  }) async {
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
        'source': source,
      });

      await p.setString(_customMemoriesKey, jsonEncode(memories));
    } catch (e) {
      debugPrint('MemoryService.addCustomMemory error: $e');
    }
  }

  /// Returns all RAG conversation memory entries (newest last).
  static Future<List<Map<String, String>>>
  getConversationMemoryEntries() async {
    try {
      final p = await _p;
      final existing = p.getString(_key);
      if (existing == null) return [];

      return List<Map<String, String>>.from(
        (jsonDecode(existing) as List<dynamic>).map(
          (e) => Map<String, String>.from(e as Map),
        ),
      );
    } catch (e) {
      debugPrint('MemoryService.getConversationMemoryEntries error: $e');

      return [];
    }
  }

  /// Deletes a RAG entry by matching query+time (stable enough for UI).
  static Future<void> deleteConversationMemoryEntry({
    required String query,
    required String time,
  }) async {
    try {
      final p = await _p;
      final existing = p.getString(_key);
      if (existing == null) return;

      final entries = List<Map<String, String>>.from(
        (jsonDecode(existing) as List<dynamic>).map(
          (e) => Map<String, String>.from(e as Map),
        ),
      );
      entries.removeWhere((e) => e['query'] == query && e['time'] == time);
      await p.setString(_key, jsonEncode(entries));
    } catch (e) {
      debugPrint('MemoryService.deleteConversationMemoryEntry error: $e');
    }
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
    } catch (e) {
      debugPrint('MemoryService.updateCustomMemory error: $e');
    }
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
    } catch (e) {
      debugPrint('MemoryService.deleteCustomMemory error: $e');
    }
  }

  /// Deletes every custom memory entry.
  static Future<void> clearAllCustomMemories() async {
    try {
      final p = await _p;
      await p.remove(_customMemoriesKey);
    } catch (e) {
      debugPrint('MemoryService.clearAllCustomMemories error: $e');
    }
  }

  /// Deletes every RAG conversation memory entry.
  static Future<void> clearConversationMemory() async {
    try {
      final p = await _p;
      await p.remove(_key);
    } catch (e) {
      debugPrint('MemoryService.clearConversationMemory error: $e');
    }
  }

  static Future<String?> retrieveContext(
    String query, {
    String? conversationSummary,
  }) async {
    final buffer = StringBuffer();

    if (conversationSummary != null && conversationSummary.isNotEmpty) {
      buffer.writeln('Conversation summary:');
      buffer.writeln(conversationSummary);
    }

    final kbContext = await KnowledgeBaseService.instance.retrieveContext(
      query,
    );
    if (kbContext != null) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(kbContext);
    }

    final customContext = await retrieveCustomMemoriesContext(query);
    if (customContext != null) {
      if (buffer.isNotEmpty) buffer.writeln();
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

      final queryTokens = SemanticSearch.tokenize(query);
      if (queryTokens.isEmpty) return null;

      final docTokensList = memories.map((m) {
        final text = '${m['title']} ${m['content']}';
        return SemanticSearch.tokenize(text);
      }).toList();

      final results = SemanticSearch.search(
        queryTokens: queryTokens,
        documents: docTokensList,
        topK: 5,
        minScore: 0.1,
      );

      if (results.isEmpty) return null;

      final buf = StringBuffer('Custom memories:\n');
      for (final r in results) {
        final m = memories[r.index];
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

      final queryTokens = SemanticSearch.tokenize(query);
      if (queryTokens.isEmpty) return null;

      final docTokensList = entries.map((e) {
        final text = '${e['query']} ${e['response']}';
        return SemanticSearch.tokenize(text);
      }).toList();

      final results = SemanticSearch.search(
        queryTokens: queryTokens,
        documents: docTokensList,
        topK: 5,
        minScore: 0.1,
      );

      if (results.isEmpty) return null;

      // Apply recency bonus to TF-IDF scores
      final scored = results.map((r) {
        final entry = entries[r.index];
        final ageInDays = DateTime.now()
            .difference(DateTime.parse(entry['time'] as String))
            .inDays;
        final recencyBonus = ageInDays == 0
            ? 1.5
            : 1.0 / (1.0 + ageInDays * 0.05);
        return MapEntry(entry, r.score * recencyBonus);
      }).toList();

      scored.sort((a, b) => b.value.compareTo(a.value));

      final buf = StringBuffer('Relevant past conversation:\n');
      for (final entry in scored) {
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
    } catch (e) {
      debugPrint('MemoryService.clearConversationHistory error: $e');
    }
  }

  static Future<void> clearCustomMemories() async {
    try {
      final p = await _p;
      await p.remove(_customMemoriesKey);
    } catch (e) {
      debugPrint('MemoryService.clearCustomMemories error: $e');
    }
  }

  static Future<void> clear() async {
    await clearConversationHistory();
    await clearCustomMemories();
  }
}

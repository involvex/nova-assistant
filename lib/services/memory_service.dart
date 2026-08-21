import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/services/knowledge_base_service.dart';
import 'package:nova_assistant/services/semantic_search.dart';

class MemoryService {
  static const _key = 'rag_conversations';
  static const _customMemoriesKey = 'custom_memories';
  static const _maxEntries = 50;
  static const _maxEntryLength = 1000;

  static List<List<String>>? _cachedCustomMemoryTokens;
  static List<List<String>>? _cachedConversationTokens;

  static File? _file;
  static List<Map<String, String>>? _conversationCache;
  static List<Map<String, dynamic>>? _customMemoriesCache;
  static Timer? _writeTimer;
  static bool _writeScheduled = false;
  static bool _cacheLoaded = false;

  static Future<File> get _dataFile async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/memory_service_data.json');
    return _file!;
  }

  static void _invalidateCustomMemoryTokens() {
    _cachedCustomMemoryTokens = null;
  }

  static void _invalidateConversationTokens() {
    _cachedConversationTokens = null;
  }

  static Future<void> _scheduleWrite() async {
    if (_writeScheduled) return;
    _writeScheduled = true;
    _writeTimer?.cancel();
    _writeTimer = Timer(const Duration(milliseconds: 300), () async {
      _writeScheduled = false;
      await _flushToDisk();
    });
  }

  static Future<void> _flushToDisk() async {
    try {
      final file = await _dataFile;
      final data = <String, dynamic>{
        _key: _conversationCache ?? const [],
        _customMemoriesKey: _customMemoriesCache ?? const [],
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('MemoryService write error: $e');
    }
  }

  static Future<void> _loadFromDisk() async {
    if (_cacheLoaded) return;
    try {
      final file = await _dataFile;
      if (!await file.exists()) {
        _conversationCache = null;
        _customMemoriesCache = null;
        _cacheLoaded = true;
        return;
      }
      final json = await file.readAsString();
      final data = jsonDecode(json) as Map<String, dynamic>;
      final conv = data[_key] as List<dynamic>?;
      _conversationCache = conv
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList();
      final custom = data[_customMemoriesKey] as List<dynamic>?;
      _customMemoriesCache = custom
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _cacheLoaded = true;
    } catch (e) {
      debugPrint('MemoryService load error: $e');
      _conversationCache = null;
      _customMemoriesCache = null;
      _cacheLoaded = true;
    }
  }

  static Future<void> initialize() async {
    await _loadFromDisk();
  }

  static Future<void> storeConversation(String query, String response) async {
    final isEnabled = await _isConversationMemoryEnabled();
    if (!isEnabled) return;

    try {
      if (!_cacheLoaded) await _loadFromDisk();
      final entries = _conversationCache ?? <Map<String, String>>[];

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

      _conversationCache = entries;
      _invalidateConversationTokens();
      await _scheduleWrite();
    } catch (e) {
      debugPrint('MemoryService.storeConversation error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getCustomMemories() async {
    try {
      await _loadFromDisk();
      return _customMemoriesCache ?? const [];
    } catch (e) {
      debugPrint('MemoryService.getCustomMemories error: $e');
      return const [];
    }
  }

  static Future<void> addCustomMemory(
    String title,
    String content, {
    String source = 'manual',
  }) async {
    try {
      if (!_cacheLoaded) await _loadFromDisk();
      final memories = _customMemoriesCache ?? <Map<String, dynamic>>[];

      memories.add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': title,
        'content': content,
        'createdAt': DateTime.now().toIso8601String(),
        'source': source,
      });

      _customMemoriesCache = memories;
      _invalidateCustomMemoryTokens();
      await _scheduleWrite();
    } catch (e) {
      debugPrint('MemoryService.addCustomMemory error: $e');
    }
  }

  static Future<List<Map<String, String>>>
  getConversationMemoryEntries() async {
    try {
      await _loadFromDisk();
      return _conversationCache
              ?.map((e) => Map<String, String>.from(e))
              .toList() ??
          const [];
    } catch (e) {
      debugPrint('MemoryService.getConversationMemoryEntries error: $e');
      return const [];
    }
  }

  static Future<void> deleteConversationMemoryEntry({
    required String query,
    required String time,
  }) async {
    try {
      if (!_cacheLoaded) await _loadFromDisk();
      final entries = _conversationCache ?? <Map<String, String>>[];
      entries.removeWhere((e) => e['query'] == query && e['time'] == time);
      _conversationCache = entries;
      _invalidateConversationTokens();
      await _scheduleWrite();
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
      if (!_cacheLoaded) await _loadFromDisk();
      final memories = _customMemoriesCache ?? <Map<String, dynamic>>[];

      final index = memories.indexWhere((m) => m['id'] == id);
      if (index != -1) {
        memories[index] = {
          ...memories[index],
          'title': title,
          'content': content,
        };
        _customMemoriesCache = memories;
        _invalidateCustomMemoryTokens();
        await _scheduleWrite();
      }
    } catch (e) {
      debugPrint('MemoryService.updateCustomMemory error: $e');
    }
  }

  static Future<void> deleteCustomMemory(String id) async {
    try {
      if (!_cacheLoaded) await _loadFromDisk();
      final memories = _customMemoriesCache ?? <Map<String, dynamic>>[];

      memories.removeWhere((m) => m['id'] == id);
      _customMemoriesCache = memories;
      _invalidateCustomMemoryTokens();
      await _scheduleWrite();
    } catch (e) {
      debugPrint('MemoryService.deleteCustomMemory error: $e');
    }
  }

  static Future<void> clearAllCustomMemories() async {
    try {
      _customMemoriesCache = const [];
      _invalidateCustomMemoryTokens();
      await _scheduleWrite();
    } catch (e) {
      debugPrint('MemoryService.clearAllCustomMemories error: $e');
    }
  }

  static Future<void> clearConversationMemory() async {
    try {
      _conversationCache = const [];
      _invalidateConversationTokens();
      await _scheduleWrite();
    } catch (e) {
      debugPrint('MemoryService.clearConversationMemory error: $e');
    }
  }

  static Future<String?> retrieveContext(
    String query, {
    String? conversationSummary,
  }) async {
    final parts = <String>[];

    if (conversationSummary != null && conversationSummary.isNotEmpty) {
      parts.add('Conversation summary:\n$conversationSummary');
    }

    final results = await Future.wait([
      KnowledgeBaseService.instance.retrieveContext(query),
      retrieveCustomMemoriesContext(query),
      _retrieveConversationContext(query),
    ]);

    parts.addAll(results.whereType<String>());

    return parts.isEmpty ? null : parts.join('\n\n');
  }

  static Future<String?> retrieveCustomMemoriesContext(String query) async {
    final isEnabled = await _isCustomMemoryEnabled();
    if (!isEnabled) return null;

    try {
      final memories = await getCustomMemories();
      if (memories.isEmpty) return null;

      final queryTokens = SemanticSearch.tokenize(query);
      if (queryTokens.isEmpty) return null;

      _cachedCustomMemoryTokens ??= memories.map((m) {
        final text = '${m['title']} ${m['content']}';
        return SemanticSearch.tokenize(text);
      }).toList();

      final docTokensList = _cachedCustomMemoryTokens!;

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
      await _loadFromDisk();
      final entries = _conversationCache;
      if (entries == null || entries.isEmpty) return null;

      final queryTokens = SemanticSearch.tokenize(query);
      if (queryTokens.isEmpty) return null;

      _cachedConversationTokens ??= entries.map((e) {
        final text = '${e['query']} ${e['response']}';
        return SemanticSearch.tokenize(text);
      }).toList();

      final docTokensList = _cachedConversationTokens!;

      final results = SemanticSearch.search(
        queryTokens: queryTokens,
        documents: docTokensList,
        topK: 5,
        minScore: 0.1,
      );

      if (results.isEmpty) return null;

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
    final p = await SharedPreferences.getInstance();
    return p.getBool('settings_rag_memory') ?? false;
  }

  static Future<bool> _isCustomMemoryEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('settings_custom_memory') ?? true;
  }

  static Future<void> clearConversationHistory() async {
    _conversationCache = const [];
    _invalidateConversationTokens();
    await _scheduleWrite();
  }

  static Future<void> clearCustomMemories() async {
    _customMemoriesCache = const [];
    _invalidateCustomMemoryTokens();
    await _scheduleWrite();
  }

  static Future<void> clear() async {
    await clearConversationHistory();
    await clearCustomMemories();
  }
}

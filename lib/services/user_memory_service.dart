import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/models/assistant_language.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/semantic_search.dart';

enum StoredMemorySource { manual, promoted }

enum DerivedMemoryOrigin { rag, summary }

class StoredMemoryItem {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final StoredMemorySource source;

  const StoredMemoryItem({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.source = StoredMemorySource.manual,
  });

  /// First-person line for inventory lists.
  String firstPersonText({bool german = false}) {
    final body = content.trim().isNotEmpty ? content.trim() : title.trim();
    final lower = body.toLowerCase();
    if (lower.startsWith('ich ') ||
        lower.startsWith("i'm ") ||
        lower.startsWith('i am ') ||
        lower.startsWith('i ')) {
      return body;
    }
    if (title.trim().isNotEmpty && content.trim().isNotEmpty) {
      final prefix = german ? 'Ich' : 'I';

      return '$prefix: $title — $content';
    }

    final prefix = german ? 'Ich' : 'I';

    return '$prefix: $body';
  }

  factory StoredMemoryItem.fromJson(Map<String, dynamic> json) {
    final sourceRaw = json['source'] as String? ?? 'manual';

    return StoredMemoryItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: sourceRaw == 'promoted'
          ? StoredMemorySource.promoted
          : StoredMemorySource.manual,
    );
  }
}

class DerivedMemoryItem {
  final String id;
  final String text;
  final DateTime derivedAt;
  final DerivedMemoryOrigin origin;
  final String originRef;

  const DerivedMemoryItem({
    required this.id,
    required this.text,
    required this.derivedAt,
    required this.origin,
    required this.originRef,
  });
}

/// Unified stored + live-derived user memory for the Copilot-style overview.
class UserMemoryService {
  static UserMemoryService? _instance;
  static UserMemoryService get instance => _instance ??= UserMemoryService._();
  UserMemoryService._();

  static const _dismissedKey = 'user_memory_dismissed_derived';
  static const _maxDerived = 40;
  static const _dedupeMinScore = 0.35;

  /// English inventory prompt (default UI / assistant language).
  static const inventoryChatPromptEn = '''
List everything you know about me:

1) your saved memory entries,
2) anything derived from our full chat history.

Output as a numbered list in a single code block using thinking mode with more detailed output.

Rules:
– Write each item in the first person ("I …").
– Format each item exactly as "<No>. [saved/derived](YYYY-MM-DD) I …", where YYYY-MM-DD is the creation date for saved memories or the conversation date for derived memories.
– List all [saved] items first, then all [derived] items.
– Within each group, sort by date ascending (earliest first).
– No extra commentary outside the code block.
''';

  /// German inventory prompt when assistant language is German.
  static const inventoryChatPromptDe = '''
Liste alles auf, was du über mich weißt:

1) deine gespeicherten Speichereinträge,
2) alles, was aus unserem vollständigen Chatverlauf abgeleitet wurde.

Ausgabe als nummerierte Liste in einem einzelnen Codeblock unter Verwendung des Denkmodus mit ausführlicherer Ausgabe.

Regeln:
– Schreibe jedes Element in der ersten Person („Ich …“).
– Formatiere jedes Element genau als„<No>. [gespeichert/abgeleitet](JJJJ-MM-TT) Ich …“, wobei JJJJ-MM-TT das Erstellungsdatum für gespeicherte Erinnerungen oder das Unterhaltungsdatum für abgeleitete Erinnerungen ist.
– Liste zuerst alle [gespeicherten] Elemente auf, dann alle [abgeleiteten] Elemente.
– Sortiere innerhalb jeder Gruppe nach Datum aufsteigend (frühester Wert zuerst).
– Keine zusätzlichen Kommentare außerhalb des Codeblocks.
''';

  /// @deprecated Prefer [inventoryChatPromptFor].
  static const inventoryChatPrompt = inventoryChatPromptEn;

  static String inventoryChatPromptFor(AssistantLanguage language) {
    return language.useGermanInventory
        ? inventoryChatPromptDe
        : inventoryChatPromptEn;
  }

  static Future<AssistantLanguage> loadAssistantLanguage() async {
    final prefs = await SharedPreferences.getInstance();

    return AssistantLanguage.fromString(
      prefs.getString(AssistantLanguage.prefsKey),
    );
  }

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<StoredMemoryItem>> listStored() async {
    final raw = await MemoryService.getCustomMemories();

    return raw.map(StoredMemoryItem.fromJson).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<List<DerivedMemoryItem>> listDerived() async {
    final stored = await listStored();
    final dismissed = await _loadDismissed();
    final candidates = <DerivedMemoryItem>[];

    final rag = await MemoryService.getConversationMemoryEntries();
    for (var i = 0; i < rag.length; i++) {
      final entry = rag[i];
      final query = (entry['query'] ?? '').trim();
      if (query.isEmpty) continue;
      final time = DateTime.tryParse(entry['time'] ?? '') ?? DateTime.now();
      final id = 'rag:${entry['time']}:$i';
      if (dismissed.contains(id)) continue;
      candidates.add(
        DerivedMemoryItem(
          id: id,
          text: _toFirstPersonCandidate(query),
          derivedAt: time,
          origin: DerivedMemoryOrigin.rag,
          originRef: entry['time'] ?? id,
        ),
      );
    }

    try {
      final conversations = await ChatHistoryService.loadConversations();
      for (final convo in conversations) {
        final summary = convo.summary;
        if (summary == null || summary.isEmpty) continue;
        final goals = _extractUserGoals(summary);
        for (var i = 0; i < goals.length; i++) {
          final id = 'summary:${convo.id}:$i';
          if (dismissed.contains(id)) continue;
          candidates.add(
            DerivedMemoryItem(
              id: id,
              text: _toFirstPersonCandidate(goals[i]),
              derivedAt: convo.updatedAt,
              origin: DerivedMemoryOrigin.summary,
              originRef: convo.id,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('UserMemoryService.listDerived summaries error: $e');
    }

    final deduped = <DerivedMemoryItem>[];
    for (final item in candidates) {
      if (_matchesStored(item.text, stored)) continue;
      if (deduped.any((d) => _textOverlapHigh(d.text, item.text))) continue;
      deduped.add(item);
    }

    deduped.sort((a, b) => a.derivedAt.compareTo(b.derivedAt));
    if (deduped.length <= _maxDerived) return deduped;

    return deduped.sublist(deduped.length - _maxDerived);
  }

  Future<void> promoteDerived(DerivedMemoryItem item, {String? title}) async {
    final clipped = item.text.length > 80
        ? '${item.text.substring(0, 80)}…'
        : item.text;
    await MemoryService.addCustomMemory(
      title ?? clipped,
      item.text,
      source: 'promoted',
    );
    await dismissDerived(item.id);
  }

  Future<void> dismissDerived(String id) async {
    final set = await _loadDismissed();
    set.add(id);
    final p = await _p;
    await p.setString(_dismissedKey, jsonEncode(set.toList()));
  }

  /// Dismisses every currently visible derived entry.
  Future<void> clearAllDerived() async {
    final derived = await listDerived();
    if (derived.isEmpty) return;
    final set = await _loadDismissed();
    for (final item in derived) {
      set.add(item.id);
    }
    final p = await _p;
    await p.setString(_dismissedKey, jsonEncode(set.toList()));
  }

  /// Clears all saved custom memories and dismisses all derived hints.
  Future<void> clearAllOverviewMemories() async {
    await MemoryService.clearAllCustomMemories();
    await clearAllDerived();
  }

  Future<Set<String>> _loadDismissed() async {
    try {
      final p = await _p;
      final raw = p.getString(_dismissedKey);
      if (raw == null || raw.isEmpty) return {};

      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Formats inventory per user rules (deterministic, for chat context / copy).
  String formatInventoryList({
    required List<StoredMemoryItem> stored,
    required List<DerivedMemoryItem> derived,
    bool german = false,
  }) {
    final storedSorted = List<StoredMemoryItem>.from(stored)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final derivedSorted = List<DerivedMemoryItem>.from(derived)
      ..sort((a, b) => a.derivedAt.compareTo(b.derivedAt));

    final savedTag = german ? 'gespeichert' : 'saved';
    final derivedTag = german ? 'abgeleitet' : 'derived';
    final emptyPlaceholder = german ? '(keine Einträge)' : '(no entries)';

    final lines = <String>[];
    var n = 1;
    for (final s in storedSorted) {
      final date = _formatDate(s.createdAt);
      lines.add('$n. [$savedTag]($date) ${s.firstPersonText(german: german)}');
      n++;
    }
    for (final d in derivedSorted) {
      final date = _formatDate(d.derivedAt);
      final lower = d.text.toLowerCase();
      final alreadyFirst =
          lower.startsWith('ich ') ||
          lower.startsWith("i'm ") ||
          lower.startsWith('i am ') ||
          lower.startsWith('i ');
      final text = alreadyFirst ? d.text : '${german ? 'Ich' : 'I'}: ${d.text}';
      lines.add('$n. [$derivedTag]($date) $text');
      n++;
    }

    if (lines.isEmpty) {
      return '```\n$emptyPlaceholder\n```';
    }

    return '```\n${lines.join('\n')}\n```';
  }

  Future<String> buildInventoryList({bool german = false}) async {
    final stored = await listStored();
    final derived = await listDerived();

    return formatInventoryList(
      stored: stored,
      derived: derived,
      german: german,
    );
  }

  DateTime? latestUpdate({
    required List<StoredMemoryItem> stored,
    required List<DerivedMemoryItem> derived,
  }) {
    DateTime? latest;
    for (final s in stored) {
      if (latest == null || s.createdAt.isAfter(latest)) latest = s.createdAt;
    }
    for (final d in derived) {
      if (latest == null || d.derivedAt.isAfter(latest)) latest = d.derivedAt;
    }

    return latest;
  }

  bool _matchesStored(String text, List<StoredMemoryItem> stored) {
    if (stored.isEmpty) return false;
    final queryTokens = SemanticSearch.tokenize(text);
    if (queryTokens.isEmpty) return false;

    final docs = stored
        .map((s) => SemanticSearch.tokenize('${s.title} ${s.content}'))
        .toList();
    final results = SemanticSearch.search(
      queryTokens: queryTokens,
      documents: docs,
      topK: 1,
      minScore: _dedupeMinScore,
    );

    return results.isNotEmpty;
  }

  bool _textOverlapHigh(String a, String b) {
    final ta = SemanticSearch.tokenize(a).toSet();
    final tb = SemanticSearch.tokenize(b).toSet();
    if (ta.isEmpty || tb.isEmpty) return false;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;

    return union > 0 && inter / union >= 0.7;
  }

  List<String> _extractUserGoals(String summary) {
    final lines = summary.split('\n');
    final goals = <String>[];
    var inGoals = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('user goals')) {
        inGoals = true;
        continue;
      }
      if (inGoals) {
        if (trimmed.toLowerCase().startsWith('recent turns')) break;
        if (trimmed.startsWith('-')) {
          final goal = trimmed.replaceFirst(RegExp(r'^-\s*'), '').trim();
          if (goal.isNotEmpty) goals.add(goal);
        }
      }
    }

    return goals;
  }

  String _toFirstPersonCandidate(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return cleaned;
    final clip = cleaned.length > 200
        ? '${cleaned.substring(0, 200)}…'
        : cleaned;
    final lower = clip.toLowerCase();
    if (lower.startsWith('ich ') ||
        lower.startsWith("i'm ") ||
        lower.startsWith('i am ') ||
        lower.startsWith('i ')) {
      return clip;
    }

    return 'I mentioned: $clip';
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');

    return '$y-$m-$d';
  }
}

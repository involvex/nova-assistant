import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:nova_assistant/services/document_chunker.dart';
import 'package:nova_assistant/services/document_extractor.dart';
import 'package:nova_assistant/services/semantic_search.dart';

/// A document ingested into the local knowledge base.
class KnowledgeDocument {
  final String id;
  final String name;
  final String filePath;
  final String fullText;
  final List<String> chunks;
  final DateTime createdAt;
  final int charCount;

  const KnowledgeDocument({
    required this.id,
    required this.name,
    required this.filePath,
    required this.fullText,
    required this.chunks,
    required this.createdAt,
    required this.charCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filePath': filePath,
    'fullText': fullText,
    'chunks': chunks,
    'createdAt': createdAt.toIso8601String(),
    'charCount': charCount,
  };

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) =>
      KnowledgeDocument(
        id: json['id'] as String,
        name: json['name'] as String,
        filePath: json['filePath'] as String? ?? '',
        fullText: json['fullText'] as String? ?? '',
        chunks: (json['chunks'] as List<dynamic>?)?.cast<String>() ?? const [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        charCount: json['charCount'] as int? ?? 0,
      );
}

/// Persists knowledge-base documents and retrieves RAG chunks.
class KnowledgeBaseService {
  static KnowledgeBaseService? _instance;
  static KnowledgeBaseService get instance =>
      _instance ??= KnowledgeBaseService._();
  KnowledgeBaseService._();

  static const _prefsKey = 'knowledge_base_documents';
  static const _enabledKey = 'settings_knowledge_base';
  static const enabledPrefsKey = _enabledKey;
  static const _maxStoredChars = 200000;
  static const _maxFullTextChars = 50000;

  SharedPreferences? _prefs;
  List<KnowledgeDocument>? _cache;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<bool> isEnabled() async {
    final p = await _p;

    return p.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final p = await _p;
    await p.setBool(_enabledKey, enabled);
  }

  Future<List<KnowledgeDocument>> listDocuments() async {
    if (_cache != null) return List.unmodifiable(_cache!);

    try {
      final p = await _p;
      final raw = p.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        _cache = [];

        return [];
      }
      final list = jsonDecode(raw) as List<dynamic>;
      _cache = list
          .map((e) => KnowledgeDocument.fromJson(e as Map<String, dynamic>))
          .toList();

      return List.unmodifiable(_cache!);
    } catch (e) {
      debugPrint('KnowledgeBaseService.listDocuments error: $e');
      _cache = [];

      return [];
    }
  }

  Future<void> _save(List<KnowledgeDocument> docs) async {
    final p = await _p;
    await p.setString(
      _prefsKey,
      jsonEncode(docs.map((d) => d.toJson()).toList()),
    );
    _cache = docs;
  }

  /// Ingest a file: extract text, chunk, and persist.
  Future<KnowledgeDocument?> ingestFile({
    required String filePath,
    required String fileName,
  }) async {
    final text = await DocumentExtractor.extractText(filePath, fileName);
    if (text.startsWith('[') &&
        (text.contains('not found') ||
            text.contains('Error') ||
            text.contains('unsupported') ||
            text.contains('pending'))) {
      debugPrint('KnowledgeBaseService.ingestFile failed: $text');

      return null;
    }

    final truncated = text.length > _maxFullTextChars
        ? text.substring(0, _maxFullTextChars)
        : text;
    final chunks = DocumentChunker.chunk(truncated);
    final docs = List<KnowledgeDocument>.from(await listDocuments());

    var totalChars = docs.fold<int>(0, (sum, d) => sum + d.charCount);
    while (docs.isNotEmpty && totalChars + truncated.length > _maxStoredChars) {
      totalChars -= docs.removeAt(0).charCount;
    }

    final doc = KnowledgeDocument(
      id: const Uuid().v4(),
      name: fileName,
      filePath: filePath,
      fullText: truncated,
      chunks: chunks,
      createdAt: DateTime.now(),
      charCount: truncated.length,
    );
    docs.add(doc);
    await _save(docs);

    return doc;
  }

  Future<void> deleteDocument(String id) async {
    final docs = List<KnowledgeDocument>.from(await listDocuments());
    docs.removeWhere((d) => d.id == id);
    await _save(docs);
  }

  Future<void> clear() async {
    await _save([]);
  }

  /// Retrieve relevant knowledge-base chunks for [query].
  Future<String?> retrieveContext(String query) async {
    if (!await isEnabled()) return null;

    try {
      final docs = await listDocuments();
      if (docs.isEmpty) return null;

      final queryTokens = SemanticSearch.tokenize(query);
      if (queryTokens.isEmpty) return null;

      final chunkEntries = <({String docName, String chunk})>[];
      for (final doc in docs) {
        for (final chunk in doc.chunks) {
          chunkEntries.add((docName: doc.name, chunk: chunk));
        }
      }
      if (chunkEntries.isEmpty) return null;

      final docTokensList = chunkEntries
          .map((e) => SemanticSearch.tokenize(e.chunk))
          .toList();

      final results = SemanticSearch.search(
        queryTokens: queryTokens,
        documents: docTokensList,
        topK: 4,
        minScore: 0.08,
      );
      if (results.isEmpty) return null;

      final buf = StringBuffer('Knowledge base:\n');
      for (final r in results) {
        final entry = chunkEntries[r.index];
        buf.writeln('- [${entry.docName}] ${entry.chunk}');
      }

      return buf.toString();
    } catch (e) {
      debugPrint('KnowledgeBaseService.retrieveContext error: $e');

      return null;
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';

List<Conversation> _parseConversationsJson(String json) {
  final list = jsonDecode(json) as List<dynamic>;
  return list
      .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Persists conversations as a JSON file — never in SharedPreferences.
///
/// Storing chat (especially base64 screenshots) in prefs OOMs Android when
/// Flutter decodes the prefs map across the platform channel (~256 MB Java
/// heap). Native [NovaApplication] migrates/drops the old prefs key on boot.
class ChatHistoryService {
  static const _oldKey = 'chat_history';
  static const _key = 'conversations';
  static const _fileName = 'conversations.json';
  static const _maxConversations = 40;
  static const _maxMessagesPerConversation = 200;

  /// Soft cap for the on-disk blob; oversized files are trimmed on load.
  static const _maxFileBytes = 4 * 1024 * 1024;

  static SharedPreferences? _prefs;
  static List<Conversation>? _cachedConversations;
  static File? _file;

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<File> _conversationsFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/$_fileName');

    return _file!;
  }

  /// Strips screenshot bytes — they bloated prefs to 100MB+ and crash startup.
  static Map<String, dynamic> _messageToPersistJson(ChatMessage message) {
    final json = message.toJson();
    json['imageData'] = null;

    return json;
  }

  static Conversation _sanitizeConversation(Conversation conversation) {
    final messages = conversation.messages.map((m) {
      if (m.imageData == null || m.imageData!.isEmpty) return m;
      final text = m.text.trim().isEmpty ? '[Screenshot]' : m.text;

      return ChatMessage(
        id: m.id,
        text: text,
        isUser: m.isUser,
        timestamp: m.timestamp,
        modelName: m.modelName,
        isStreaming: m.isStreaming,
        isError: m.isError,
        thinking: m.thinking,
        toolCalls: m.toolCalls,
        inferenceTimeMs: m.inferenceTimeMs,
        reactions: m.reactions,
        isPinned: m.isPinned,
      );
    }).toList();
    final trimmed = messages.length > _maxMessagesPerConversation
        ? messages.sublist(messages.length - _maxMessagesPerConversation)
        : messages;

    return conversation.copyWith(messages: trimmed);
  }

  static List<Conversation> _capConversations(List<Conversation> list) {
    final sorted = List<Conversation>.from(list)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (sorted.length <= _maxConversations) {
      return sorted.map(_sanitizeConversation).toList();
    }

    return sorted.take(_maxConversations).map(_sanitizeConversation).toList();
  }

  static Future<void> ensureMigrated() async {
    final file = await _conversationsFile();
    if (await file.exists() && await file.length() > 0) {
      // Drop leftover prefs keys if native migrate already wrote the file.
      try {
        final p = await _p;
        await p.remove(_key);
        await p.remove(_oldKey);
      } on Exception catch (e) {
        debugPrint('ChatHistoryService: prefs cleanup after file migrate: $e');
      }

      return;
    }

    // Legacy path: small prefs payloads only (native drops oversized ones).
    try {
      final p = await _p;
      final json = p.getString(_key);
      if (json != null && json.isNotEmpty) {
        await file.writeAsString(json);
        await p.remove(_key);
        debugPrint(
          'ChatHistoryService: migrated conversations prefs → file '
          '(${json.length} chars)',
        );
      }

      final oldJson = p.getString(_oldKey);
      if (oldJson != null && oldJson.isNotEmpty) {
        try {
          final list = jsonDecode(oldJson) as List<dynamic>;
          if (list.isNotEmpty) {
            final messages = list
                .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
                .toList();
            final conversation = Conversation(messages: messages);
            await _saveConversationsInternal([conversation]);
          }
        } on Exception catch (e) {
          debugPrint('ChatHistoryService: old chat_history migrate failed: $e');
        }
        await p.remove(_oldKey);
      }
    } on Exception catch (e) {
      debugPrint('ChatHistoryService.ensureMigrated prefs read failed: $e');
    }
  }

  static Future<List<Conversation>> loadConversations() async {
    if (_cachedConversations != null) {
      return List.unmodifiable(_cachedConversations!);
    }
    await ensureMigrated();
    try {
      final file = await _conversationsFile();
      final json = await file.readAsString();
      final length = json.length;
      if (length == 0) {
        _cachedConversations = [];

        return [];
      }

      if (length > _maxFileBytes * 4) {
        debugPrint(
          'ChatHistoryService: conversations file too large '
          '($length bytes) — resetting to avoid OOM',
        );
        await file.delete();
        _cachedConversations = [];

        return [];
      }

      List<Conversation> conversations;
      if (length > 500 * 1024) {
        conversations = await compute(_parseConversationsJson, json);
      } else {
        conversations = _parseConversationsJson(json);
      }
      conversations = _capConversations(conversations);
      _cachedConversations = conversations;

      if (length > _maxFileBytes) {
        await _saveConversationsInternal(conversations);
      }

      return List.unmodifiable(_cachedConversations!);
    } on Exception catch (e) {
      debugPrint('ChatHistoryService.loadConversations error: $e');
      _cachedConversations = [];

      return [];
    }
  }

  static Future<void> _saveConversationsInternal(
    List<Conversation> conversations,
  ) async {
    try {
      final capped = _capConversations(conversations);
      final encoded = jsonEncode(
        capped
            .map(
              (c) => {
                'id': c.id,
                'title': c.title,
                'messages': c.messages.map(_messageToPersistJson).toList(),
                'createdAt': c.createdAt.toIso8601String(),
                'updatedAt': c.updatedAt.toIso8601String(),
                'summary': c.summary,
              },
            )
            .toList(),
      );
      final file = await _conversationsFile();
      await file.writeAsString(encoded);
      _cachedConversations = capped;

      // Ensure prefs never holds the blob again.
      try {
        final p = await _p;
        if (p.containsKey(_key)) await p.remove(_key);
      } on Exception catch (_) {}
    } on Exception catch (e) {
      debugPrint('ChatHistoryService._saveConversationsInternal error: $e');
    }
  }

  static Future<void> saveConversations(
    List<Conversation> conversations,
  ) async {
    await _saveConversationsInternal(conversations);
  }

  static Future<Conversation> createConversation({String? title}) async {
    final conversations = await loadConversations();
    final conversation = Conversation(title: title);
    final updated = <Conversation>[conversation, ...conversations];
    await _saveConversationsInternal(updated);

    return conversation;
  }

  static Future<void> updateConversation(Conversation conversation) async {
    final conversations = await loadConversations();
    final index = conversations.indexWhere((c) => c.id == conversation.id);
    if (index != -1) {
      final updated = List<Conversation>.from(conversations);
      updated[index] = conversation.copyWith(updatedAt: DateTime.now());
      await _saveConversationsInternal(updated);
    }
  }

  static Future<void> deleteConversation(String id) async {
    final conversations = await loadConversations();
    final updated = conversations.where((c) => c.id != id).toList();
    await _saveConversationsInternal(updated);
  }

  static Future<Conversation?> getConversation(String id) async {
    final conversations = await loadConversations();

    return conversations.where((c) => c.id == id).firstOrNull;
  }

  static Future<void> appendMessage(
    String conversationId,
    ChatMessage message,
  ) async {
    final conversations = await loadConversations();
    final index = conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final conversation = conversations[index];
      final updatedMessages = <ChatMessage>[...conversation.messages, message];
      final updated = List<Conversation>.from(conversations);
      updated[index] = conversation.copyWith(
        messages: updatedMessages,
        updatedAt: DateTime.now(),
      );
      await _saveConversationsInternal(updated);
    }
  }

  static Future<List<ChatMessage>> load() async {
    final conversations = await loadConversations();
    if (conversations.isEmpty) return [];
    final first = conversations.first;

    return first.messages;
  }

  static Future<void> save(List<ChatMessage> messages) async {
    var conversations = await loadConversations();
    if (conversations.isEmpty) {
      await createConversation();
      conversations = await loadConversations();
    }
    final updated = List<Conversation>.from(conversations);
    updated[0] = updated[0].copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );
    await _saveConversationsInternal(updated);
  }

  static Future<void> append(ChatMessage message) async {
    var conversations = await loadConversations();
    if (conversations.isEmpty) {
      await createConversation();
      conversations = await loadConversations();
    }
    await appendMessage(conversations.first.id, message);
  }

  static Future<void> clear() async {
    _cachedConversations = [];
    try {
      final file = await _conversationsFile();
      if (await file.exists()) await file.delete();
    } on Exception catch (e) {
      debugPrint('ChatHistoryService.clear file error: $e');
    } finally {
      _file = null;
    }
    try {
      final p = await _p;
      await p.remove(_key);
      await p.remove(_oldKey);
    } on Exception catch (e) {
      debugPrint('ChatHistoryService.clear prefs error: $e');
    }
  }

  /// Builds a plain-text export of all conversations (no file write).
  static Future<String?> exportAsText() async {
    try {
      final conversations = await loadConversations();
      if (conversations.isEmpty) return null;

      final buffer = StringBuffer();
      buffer.writeln('Nova Assistant — All Conversations Export');
      buffer.writeln('Exported: ${DateTime.now().toLocal()}');
      buffer.writeln('Conversations: ${conversations.length}');
      buffer.writeln('=' * 50);

      for (var i = 0; i < conversations.length; i++) {
        final convo = conversations[i];
        buffer.writeln();
        buffer.writeln('CONVERSATION ${i + 1}: ${convo.previewTitle}');
        buffer.writeln('Created: ${convo.createdAt}');
        buffer.writeln('-' * 30);

        for (final msg in convo.messages) {
          _appendMessage(buffer, msg);
        }
        buffer.writeln('=' * 50);
      }

      return buffer.toString();
    } on Exception {
      return null;
    }
  }

  /// Builds a plain-text export of one conversation (no file write).
  static Future<String?> exportConversationAsText(String conversationId) async {
    try {
      final convo = await getConversation(conversationId);
      if (convo == null || convo.messages.isEmpty) return null;

      final buffer = StringBuffer();
      buffer.writeln('Nova Assistant — Conversation Export');
      buffer.writeln('Title: ${convo.previewTitle}');
      buffer.writeln('Exported: ${DateTime.now().toLocal()}');
      buffer.writeln('Messages: ${convo.messages.length}');
      buffer.writeln('---');

      for (final msg in convo.messages) {
        _appendMessage(buffer, msg);
      }

      return buffer.toString();
    } on Exception {
      return null;
    }
  }

  /// Builds a JSON export of all conversations (no file write).
  static Future<String?> exportAsJson() async {
    try {
      final conversations = await loadConversations();
      if (conversations.isEmpty) return null;

      final export = <String, dynamic>{
        'exportedAt': DateTime.now().toIso8601String(),
        'conversationCount': conversations.length,
        'conversations': conversations.map((c) => c.toJson()).toList(),
      };

      return const JsonEncoder.withIndent('  ').convert(export);
    } on Exception {
      return null;
    }
  }

  static void _appendMessage(StringBuffer buffer, ChatMessage msg) {
    final time = msg.timestamp.toLocal();
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    final sender = msg.isUser ? 'User' : 'Assistant';
    buffer.writeln('[$timeStr] $sender:');
    buffer.writeln(msg.text);
    if (msg.imageData != null) buffer.writeln('[Image attached]');
    if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
      buffer.writeln('[Tool calls: ${msg.toolCalls}]');
    }
    if (msg.thinking != null && msg.thinking!.isNotEmpty) {
      buffer.writeln('[Thinking: ${msg.thinking}]');
    }
    buffer.writeln();
  }

  /// Builds a Markdown export of one conversation (no file write).
  static Future<String?> exportConversationAsMarkdown(
    String conversationId,
  ) async {
    try {
      final convo = await getConversation(conversationId);
      if (convo == null || convo.messages.isEmpty) return null;

      final buffer = StringBuffer();
      final title = convo.previewTitle;
      buffer.writeln('# $title');
      buffer.writeln();
      buffer.writeln('*Exported: ${DateTime.now().toLocal()}*  ');
      buffer.writeln('*Messages: ${convo.messages.length}*');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();

      for (final msg in convo.messages) {
        if (msg.isUser) {
          buffer.writeln('## User');
        } else {
          buffer.writeln('## Assistant');
        }
        buffer.writeln();
        buffer.writeln(msg.text);
        buffer.writeln();
        if (msg.thinking != null && msg.thinking!.isNotEmpty) {
          buffer.writeln('**Thinking:**');
          buffer.writeln(msg.thinking!);
          buffer.writeln();
        }
        if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
          buffer.writeln('**Tool Calls:**');
          buffer.writeln('```json');
          buffer.writeln(msg.toolCalls!);
          buffer.writeln('```');
          buffer.writeln();
        }
        buffer.writeln('---');
        buffer.writeln();
      }

      return buffer.toString();
    } on Exception {
      return null;
    }
  }

  /// Creates a new conversation forked from [splitAtIndex] (inclusive).
  /// Messages before that index stay in the original conversation.
  static Future<Conversation?> forkConversation(
    String conversationId,
    int splitAtIndex,
  ) async {
    try {
      final convo = await getConversation(conversationId);
      if (convo == null) return null;
      if (splitAtIndex < 0 || splitAtIndex >= convo.messages.length) {
        return null;
      }

      final forkedMessages = convo.messages.sublist(splitAtIndex);
      final forkedConv = Conversation(
        title: '${convo.previewTitle} (fork)',
        messages: forkedMessages,
      );

      // Truncate the original conversation to messages before split point.
      final originalMessages = convo.messages.sublist(0, splitAtIndex);
      final updatedOriginal = convo.copyWith(
        messages: originalMessages,
        updatedAt: DateTime.now(),
      );

      final conversations = await loadConversations();
      final index = conversations.indexWhere((c) => c.id == conversationId);
      final updated = List<Conversation>.from(conversations);
      if (index != -1) {
        updated[index] = updatedOriginal;
      }
      updated.insert(0, forkedConv);
      await _saveConversationsInternal(updated);

      return forkedConv;
    } on Exception catch (e) {
      debugPrint('ChatHistoryService.forkConversation error: $e');
      return null;
    }
  }
}

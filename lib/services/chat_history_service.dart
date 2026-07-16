import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';

class ChatHistoryService {
  static const _oldKey = 'chat_history';
  static const _key = 'conversations';
  static const _migratedKey = 'conversations_migrated';
  static SharedPreferences? _prefs;
  static List<Conversation>? _cachedConversations;

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<void> ensureMigrated() async {
    final p = await _p;
    final alreadyMigrated = p.getBool(_migratedKey) ?? false;
    if (alreadyMigrated) return;

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
          await p.remove(_oldKey);
        }
      } catch (_) {}
    }
    await p.setBool(_migratedKey, true);
  }

  static Future<List<Conversation>> loadConversations() async {
    if (_cachedConversations != null) {
      return List.unmodifiable(_cachedConversations!);
    }
    await ensureMigrated();
    try {
      final p = await _p;
      final json = p.getString(_key);
      if (json == null || json.isEmpty) {
        _cachedConversations = [];
        return [];
      }
      final list = jsonDecode(json) as List<dynamic>;
      _cachedConversations = list
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
      _cachedConversations!.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return List.unmodifiable(_cachedConversations!);
    } catch (_) {
      _cachedConversations = [];
      return [];
    }
  }

  static Future<void> _saveConversationsInternal(
    List<Conversation> conversations,
  ) async {
    try {
      final p = await _p;
      final json = jsonEncode(conversations.map((c) => c.toJson()).toList());
      await p.setString(_key, json);
      _cachedConversations = conversations;
    } catch (e) {
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

  static Future<void> updateMessage(
    String conversationId,
    ChatMessage message,
  ) async {
    final conversations = await loadConversations();
    final convoIndex = conversations.indexWhere((c) => c.id == conversationId);
    if (convoIndex != -1) {
      final conversation = conversations[convoIndex];
      final messages = List<ChatMessage>.from(conversation.messages);
      final msgIndex = messages.indexWhere((m) => m.id == message.id);
      if (msgIndex != -1) {
        messages[msgIndex] = message;
        final updated = List<Conversation>.from(conversations);
        updated[convoIndex] = conversation.copyWith(
          messages: messages,
          updatedAt: DateTime.now(),
        );
        await _saveConversationsInternal(updated);
      }
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
    final p = await _p;
    await p.remove(_key);
  }

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
          final time = msg.timestamp.toLocal();
          final timeStr =
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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
        buffer.writeln('=' * 50);
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/nova_export_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await file.writeAsString(buffer.toString());
      return file.path;
    } on Exception {
      return null;
    }
  }

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
        final time = msg.timestamp.toLocal();
        final timeStr =
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/nova_export_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await file.writeAsString(buffer.toString());
      return file.path;
    } on Exception {
      return null;
    }
  }

  static Future<String?> exportAsJson() async {
    try {
      final conversations = await loadConversations();
      if (conversations.isEmpty) return null;

      final export = <String, dynamic>{
        'exportedAt': DateTime.now().toIso8601String(),
        'conversationCount': conversations.length,
        'conversations': conversations.map((c) => c.toJson()).toList(),
      };

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/nova_export_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonEncode(export));
      return file.path;
    } on Exception {
      return null;
    }
  }
}

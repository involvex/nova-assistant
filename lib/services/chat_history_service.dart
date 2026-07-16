import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/chat_message.dart';

class ChatHistoryService {
  static const _key = 'chat_history';
  static SharedPreferences? _prefs;
  static List<ChatMessage>? _cachedMessages;
  static bool _cacheDirty = false;

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<List<ChatMessage>> load() async {
    if (_cachedMessages != null) return List.unmodifiable(_cachedMessages!);
    try {
      final p = await _p;
      final json = p.getString(_key);
      if (json == null || json.isEmpty) {
        _cachedMessages = [];
        return [];
      }
      final list = jsonDecode(json) as List<dynamic>;
      _cachedMessages = list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      return List.unmodifiable(_cachedMessages!);
    } catch (_) {
      _cachedMessages = [];
      return [];
    }
  }

  static Future<void> save(List<ChatMessage> messages) async {
    try {
      final p = await _p;
      final json = jsonEncode(messages.map((m) => m.toJson()).toList());
      await p.setString(_key, json);
      _cacheDirty = false;
    } catch (e) {
      debugPrint('ChatHistoryService.save error: $e');
    }
  }

  static Future<void> _flush() async {
    if (_cacheDirty && _cachedMessages != null) {
      await save(_cachedMessages!);
    }
  }

  static Future<void> append(ChatMessage message) async {
    if (_cachedMessages == null) {
      await load();
    }
    _cachedMessages!.add(message);
    _cacheDirty = true;
    await _flush();
  }

  static Future<void> clear() async {
    try {
      _cachedMessages = [];
      _cacheDirty = false;
      final p = await _p;
      await p.remove(_key);
    } catch (e) {
      debugPrint('ChatHistoryService.clear error: $e');
    }
  }

  static Future<String?> exportAsText() async {
    try {
      final messages = await load();
      if (messages.isEmpty) return null;

      final buffer = StringBuffer();
      buffer.writeln('Nova Assistant — Conversation Export');
      buffer.writeln('Exported: ${DateTime.now().toLocal()}');
      buffer.writeln('Messages: ${messages.length}');
      buffer.writeln('---');
      buffer.writeln();

      for (final msg in messages) {
        final time = msg.timestamp.toLocal();
        final timeStr =
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
        final sender = msg.isUser ? '👤 User' : '🤖 Assistant';
        buffer.writeln('[$timeStr] $sender:');
        buffer.writeln(msg.text);
        if (msg.imageData != null) {
          buffer.writeln('[Image attached]');
        }
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
      final messages = await load();
      if (messages.isEmpty) return null;

      final export = <String, dynamic>{
        'exportedAt': DateTime.now().toIso8601String(),
        'messageCount': messages.length,
        'messages': messages.map((m) => m.toJson()).toList(),
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

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/chat_message.dart';

class ChatHistoryService {
  static const _key = 'chat_history';
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<List<ChatMessage>> load() async {
    try {
      final p = await _p;
      final json = p.getString(_key);
      if (json == null || json.isEmpty) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<ChatMessage> messages) async {
    try {
      final p = await _p;
      final json = jsonEncode(messages.map((m) => m.toJson()).toList());
      await p.setString(_key, json);
    } catch (_) {}
  }

  static Future<void> append(ChatMessage message) async {
    final messages = await load();
    messages.add(message);
    await save(messages);
  }

  static Future<void> clear() async {
    try {
      final p = await _p;
      await p.remove(_key);
    } catch (_) {}
  }
}

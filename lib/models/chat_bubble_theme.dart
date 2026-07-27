import 'package:flutter/material.dart';

enum ChatBubbleThemeType { defaultTheme, ocean, forest, neon }

class ChatBubbleTheme {
  const ChatBubbleTheme({
    required this.name,
    required this.type,
    required this.userBubbleColor,
    required this.assistantBubbleColor,
    required this.backgroundColor,
    required this.userTextColor,
    required this.assistantTextColor,
    required this.accentColor,
  });

  final String name;
  final ChatBubbleThemeType type;
  final Color userBubbleColor;
  final Color assistantBubbleColor;
  final Color backgroundColor;
  final Color userTextColor;
  final Color assistantTextColor;
  final Color accentColor;

  static const defaultTheme = ChatBubbleTheme(
    name: 'Default',
    type: ChatBubbleThemeType.defaultTheme,
    userBubbleColor: Color(0xFF6C63FF),
    assistantBubbleColor: Color(0xFF1A1A2E),
    backgroundColor: Color(0xFF0D0D1A),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF6C63FF),
  );

  static const ocean = ChatBubbleTheme(
    name: 'Ocean',
    type: ChatBubbleThemeType.ocean,
    userBubbleColor: Color(0xFF0077B6),
    assistantBubbleColor: Color(0xFF023E8A),
    backgroundColor: Color(0xFF03045E),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF00B4D8),
  );

  static const forest = ChatBubbleTheme(
    name: 'Forest',
    type: ChatBubbleThemeType.forest,
    userBubbleColor: Color(0xFF2D6A4F),
    assistantBubbleColor: Color(0xFF1B4332),
    backgroundColor: Color(0xFF081C15),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF52B788),
  );

  static const neon = ChatBubbleTheme(
    name: 'Neon',
    type: ChatBubbleThemeType.neon,
    userBubbleColor: Color(0xFFFF006E),
    assistantBubbleColor: Color(0xFF1A1A2E),
    backgroundColor: Color(0xFF0D0D1A),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF8338EC),
  );

  static const values = [defaultTheme, ocean, forest, neon];

  static ChatBubbleTheme fromType(ChatBubbleThemeType type) {
    return values.firstWhere((t) => t.type == type, orElse: () => defaultTheme);
  }
}

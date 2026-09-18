import 'package:flutter/material.dart';
import 'package:nova_assistant/theme/nova_palettes.dart';

/// Legacy chat-bubble theme wrapper — maps onto [NovaPalette].
enum ChatBubbleThemeType {
  defaultTheme,
  hacker,
  monokai,
  dracula,
  ocean,
  forest,
  neon,
}

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

  factory ChatBubbleTheme.fromPalette(NovaPalette palette) {
    return ChatBubbleTheme(
      name: palette.name,
      type: ChatBubbleThemeType.values.firstWhere(
        (t) => t.name == palette.id.name,
        orElse: () => ChatBubbleThemeType.defaultTheme,
      ),
      userBubbleColor: palette.userBubble,
      assistantBubbleColor: palette.assistantBubble,
      backgroundColor: palette.chatBackground,
      userTextColor: Colors.white,
      assistantTextColor: const Color(0xEBFFFFFF),
      accentColor: palette.accent,
    );
  }

  static ChatBubbleTheme get defaultTheme =>
      ChatBubbleTheme.fromPalette(NovaPalette.defaultTheme);
  static ChatBubbleTheme get hacker =>
      ChatBubbleTheme.fromPalette(NovaPalette.hacker);
  static ChatBubbleTheme get monokai =>
      ChatBubbleTheme.fromPalette(NovaPalette.monokai);
  static ChatBubbleTheme get dracula =>
      ChatBubbleTheme.fromPalette(NovaPalette.dracula);
  static ChatBubbleTheme get ocean =>
      ChatBubbleTheme.fromPalette(NovaPalette.ocean);
  static ChatBubbleTheme get forest =>
      ChatBubbleTheme.fromPalette(NovaPalette.forest);
  static ChatBubbleTheme get neon =>
      ChatBubbleTheme.fromPalette(NovaPalette.neon);

  static List<ChatBubbleTheme> get values => NovaPalette.values
      .map(ChatBubbleTheme.fromPalette)
      .toList(growable: false);

  static ChatBubbleTheme fromType(ChatBubbleThemeType type) {
    final paletteId =
        NovaPalette.parseId(type.name) ?? NovaPaletteId.defaultTheme;
    return ChatBubbleTheme.fromPalette(NovaPalette.fromId(paletteId));
  }
}

import 'package:flutter/material.dart';

/// Named app color palettes for Material chrome and chat bubbles.
enum NovaPaletteId {
  defaultTheme,
  hacker,
  monokai,
  dracula,
  ocean,
  forest,
  neon,
}

class NovaPalette {
  const NovaPalette({
    required this.id,
    required this.name,
    required this.seed,
    required this.scaffoldDark,
    required this.cardDark,
    required this.scaffoldLight,
    required this.cardLight,
    required this.userBubble,
    required this.assistantBubble,
    required this.chatBackground,
    required this.accent,
  });

  final NovaPaletteId id;
  final String name;
  final Color seed;
  final Color scaffoldDark;
  final Color cardDark;
  final Color scaffoldLight;
  final Color cardLight;
  final Color userBubble;
  final Color assistantBubble;
  final Color chatBackground;
  final Color accent;

  static const defaultTheme = NovaPalette(
    id: NovaPaletteId.defaultTheme,
    name: 'Default',
    seed: Color(0xFF6C63FF),
    scaffoldDark: Color(0xFF0D0D1A),
    cardDark: Color(0xFF1A1A2E),
    scaffoldLight: Color(0xFFF7F7FF),
    cardLight: Colors.white,
    userBubble: Color(0xFF6C63FF),
    assistantBubble: Color(0xFF1A1A2E),
    chatBackground: Color(0xFF0D0D1A),
    accent: Color(0xFF6C63FF),
  );

  static const hacker = NovaPalette(
    id: NovaPaletteId.hacker,
    name: 'Hacker',
    seed: Color(0xFF00FF41),
    scaffoldDark: Color(0xFF0A0F0A),
    cardDark: Color(0xFF121A12),
    scaffoldLight: Color(0xFFF0FFF2),
    cardLight: Color(0xFFE8F5E9),
    userBubble: Color(0xFF00C853),
    assistantBubble: Color(0xFF1B2E1B),
    chatBackground: Color(0xFF0A0F0A),
    accent: Color(0xFF00FF41),
  );

  static const monokai = NovaPalette(
    id: NovaPaletteId.monokai,
    name: 'Monokai',
    seed: Color(0xFFF92672),
    scaffoldDark: Color(0xFF272822),
    cardDark: Color(0xFF3E3D32),
    scaffoldLight: Color(0xFFF8F8F2),
    cardLight: Colors.white,
    userBubble: Color(0xFFF92672),
    assistantBubble: Color(0xFF3E3D32),
    chatBackground: Color(0xFF272822),
    accent: Color(0xFFA6E22E),
  );

  static const dracula = NovaPalette(
    id: NovaPaletteId.dracula,
    name: 'Dracula',
    seed: Color(0xFFBD93F9),
    scaffoldDark: Color(0xFF282A36),
    cardDark: Color(0xFF44475A),
    scaffoldLight: Color(0xFFF8F8F2),
    cardLight: Colors.white,
    userBubble: Color(0xFFBD93F9),
    assistantBubble: Color(0xFF44475A),
    chatBackground: Color(0xFF282A36),
    accent: Color(0xFFFF79C6),
  );

  static const ocean = NovaPalette(
    id: NovaPaletteId.ocean,
    name: 'Ocean',
    seed: Color(0xFF00B4D8),
    scaffoldDark: Color(0xFF03045E),
    cardDark: Color(0xFF023E8A),
    scaffoldLight: Color(0xFFE8F8FF),
    cardLight: Colors.white,
    userBubble: Color(0xFF0077B6),
    assistantBubble: Color(0xFF023E8A),
    chatBackground: Color(0xFF03045E),
    accent: Color(0xFF00B4D8),
  );

  static const forest = NovaPalette(
    id: NovaPaletteId.forest,
    name: 'Forest',
    seed: Color(0xFF52B788),
    scaffoldDark: Color(0xFF081C15),
    cardDark: Color(0xFF1B4332),
    scaffoldLight: Color(0xFFF0FFF4),
    cardLight: Colors.white,
    userBubble: Color(0xFF2D6A4F),
    assistantBubble: Color(0xFF1B4332),
    chatBackground: Color(0xFF081C15),
    accent: Color(0xFF52B788),
  );

  static const neon = NovaPalette(
    id: NovaPaletteId.neon,
    name: 'Neon',
    seed: Color(0xFFFF006E),
    scaffoldDark: Color(0xFF0D0D1A),
    cardDark: Color(0xFF1A1A2E),
    scaffoldLight: Color(0xFFFFF0F6),
    cardLight: Colors.white,
    userBubble: Color(0xFFFF006E),
    assistantBubble: Color(0xFF1A1A2E),
    chatBackground: Color(0xFF0D0D1A),
    accent: Color(0xFF8338EC),
  );

  static const values = [
    defaultTheme,
    hacker,
    monokai,
    dracula,
    ocean,
    forest,
    neon,
  ];

  static NovaPalette fromId(NovaPaletteId id) {
    return values.firstWhere((p) => p.id == id, orElse: () => defaultTheme);
  }

  static NovaPaletteId? parseId(String? name) {
    if (name == null) return null;
    for (final id in NovaPaletteId.values) {
      if (id.name == name) return id;
    }
    // Migrate legacy bubble theme prefs.
    switch (name) {
      case 'defaultTheme':
        return NovaPaletteId.defaultTheme;
      case 'ocean':
        return NovaPaletteId.ocean;
      case 'forest':
        return NovaPaletteId.forest;
      case 'neon':
        return NovaPaletteId.neon;
      default:
        return null;
    }
  }

  ThemeData buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
      ),
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: scaffoldLight,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldLight,
        elevation: 0,
        centerTitle: true,
        foregroundColor: const Color(0xFF1A1A2E),
      ),
      cardTheme: CardThemeData(
        color: cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
    );
  }

  ThemeData buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: scaffoldDark,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldDark,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
    );
  }
}

import 'package:nova_assistant/ai/router/intent.dart';

/// Classifies a user query. V1 is rule-based (DE/EN keywords);
/// V2 can swap in a small local model behind the same interface.
abstract class IntentRouter {
  Future<Intent> route(
    String query, {
    bool hasImage = false,
    String? activePackage,
  });
}

class RuleBasedIntentRouter implements IntentRouter {
  const RuleBasedIntentRouter();

  static const List<String> _visionKeywords = <String>[
    'bildschirm',
    'screen',
    'screenshot',
    'was sehe ich',
    'what do you see',
    'was siehst du',
    'analysiere den bildschirm',
    'analyze the screen',
    'foto',
    'photo',
    'bild',
    'image',
  ];

  // Note: plain time/date questions ('Wie spät ist es?') stay Intent.local
  // per spec — the model answers from context, no device action needed.
  // Only alarm/timer management is a tool intent.
  static const List<String> _toolKeywords = <String>[
    'öffne',
    'open',
    'launch',
    'starte',
    'wecker',
    'alarm',
    'timer',
    'erinnere',
    'remind',
    'sms',
    'anruf',
    'einstellungen',
    'settings',
    'lautstärke',
    'volume',
    'bluetooth',
    'wlan',
    'wifi',
  ];

  static const List<String> _automationKeywords = <String>[
    'automatisiere',
    'automate',
    'workflow',
    'routine',
    'jedes mal wenn',
    'wenn ich',
    'tasker',
    'makro',
    'macro',
    'batch',
    'stapel',
  ];

  static const List<String> _cloudKeywords = <String>[
    'analysiere diese apk',
    'analyze this apk',
    'reverse engineer',
    'programmier',
    'coding',
    'refactor',
    'schreibe code',
    'write code',
    'schreib code',
    ' code ',
    'code ',
    ' code',
    'funktion ',
    'function',
    'python',
    'javascript',
    'typescript',
    'dart ',
    'flutter',
    ' fehler',
    'fehler',
    'debug',
    'bugfix',
    'algorithmus',
    'regex',
    'skript',
    'script',
    'datenbank',
    'database',
    ' sql',
    ' api',
    'server',
    'compiler',
    'kompilier',
    'übersetze den roman',
    'dissertation',
    'recherche',
    'deep research',
    'vergleiche',
    'complex',
    'komplex',
    'nutze cloud',
    'use cloud',
    'claude',
    'gpt-',
    'gpt ',
    'gemini',
    'starkes modell',
    'größeres modell',
    'grosse analyse',
    'große analyse',
  ];

  @override
  Future<Intent> route(
    String query, {
    bool hasImage = false,
    String? activePackage,
  }) async {
    final String lower = query.toLowerCase();

    if (hasImage || _containsAny(lower, _visionKeywords)) {
      return Intent.vision;
    }
    if (_containsAny(lower, _automationKeywords)) {
      return Intent.automation;
    }
    if (_containsAny(lower, _toolKeywords)) {
      return Intent.tool;
    }
    if (_containsAny(lower, _cloudKeywords) || lower.length > 400) {
      return Intent.cloud;
    }

    return Intent.local;
  }

  bool _containsAny(String haystack, List<String> needles) {
    for (final String needle in needles) {
      if (haystack.contains(needle.toLowerCase())) {
        return true;
      }
    }

    return false;
  }
}

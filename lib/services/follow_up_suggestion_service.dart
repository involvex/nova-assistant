import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Generates contextual follow-up question chips for the chat input bar.
class FollowUpSuggestionService {
  static FollowUpSuggestionService? _instance;
  static FollowUpSuggestionService get instance =>
      _instance ??= FollowUpSuggestionService._();
  FollowUpSuggestionService._();

  static const starterSuggestions = <String>[
    "What's on my screen?",
    'Set an alarm for 7:00 PM',
    'Summarize this page',
  ];

  /// Parse model JSON output into up to 3 suggestion strings.
  static List<String> parseSuggestions(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return [];

    try {
      final start = trimmed.indexOf('[');
      final end = trimmed.lastIndexOf(']');
      if (start != -1 && end > start) {
        final decoded = jsonDecode(trimmed.substring(start, end + 1));
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .take(3)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('FollowUpSuggestionService.parseSuggestions: $e');
    }

    return [];
  }

  Future<List<String>> suggest({
    String? lastUserMessage,
    String? lastAssistantMessage,
    bool different = false,
  }) async {
    if ((lastUserMessage == null || lastUserMessage.isEmpty) &&
        (lastAssistantMessage == null || lastAssistantMessage.isEmpty)) {
      return List<String>.from(starterSuggestions);
    }

    final user = lastUserMessage ?? '';
    final assistant = lastAssistantMessage ?? '';
    final heuristic = _heuristicSuggestions(
      user: user,
      assistant: assistant,
      different: different,
    );
    if (heuristic.isNotEmpty) return heuristic;

    return _genericSuggestions(different: different);
  }

  List<String> _heuristicSuggestions({
    required String user,
    required String assistant,
    required bool different,
  }) {
    final combined = '${user.toLowerCase()} ${assistant.toLowerCase()}';

    if (combined.contains('weather') ||
        combined.contains('rain') ||
        combined.contains('temperature') ||
        combined.contains('forecast')) {
      return different
          ? const [
              'What is the temperature in Celsius?',
              'Will it rain later today?',
              'What about tomorrow?',
            ]
          : const [
              'How many degrees is it?',
              'Will it stay rainy all day?',
              'What is the forecast for tomorrow?',
            ];
    }

    if (combined.contains('alarm') || combined.contains('remind')) {
      return different
          ? const [
              'Can you set another alarm?',
              'Cancel my last alarm',
              'What time is it now?',
            ]
          : const [
              'Set an alarm for tomorrow morning',
              'Change that alarm to 8 AM',
              'What alarms do I have?',
            ];
    }

    if (combined.contains('screen') || combined.contains('screenshot')) {
      return different
          ? const [
              'What app is open?',
              'Summarize what you see',
              'Is there anything important on screen?',
            ]
          : const [
              'Describe the screen in more detail',
              'What text can you read?',
              'Is there an error message visible?',
            ];
    }

    if (combined.contains('code') ||
        combined.contains('bug') ||
        combined.contains('error')) {
      return different
          ? const [
              'How can I fix this?',
              'Show a simpler example',
              'What should I test next?',
            ]
          : const [
              'Explain that step by step',
              'What is the root cause?',
              'Can you suggest a refactor?',
            ];
    }

    return [];
  }

  List<String> _genericSuggestions({required bool different}) {
    final sets = <List<String>>[
      const [
        'Can you explain that in simpler terms?',
        'What are the next steps?',
        'Anything else I should know?',
      ],
      const [
        'Give me more detail',
        'Summarize the key points',
        'What would you recommend?',
      ],
    ];
    final index = different ? 1 : 0;

    return sets[index];
  }
}

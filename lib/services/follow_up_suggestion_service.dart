import 'package:flutter/foundation.dart';

import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/utils/suggestion_json_parser.dart';

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
  static List<String> parseSuggestions(String raw) =>
      SuggestionJsonParser.parseStringList(raw, max: 3);

  Future<List<String>> suggest({
    String? lastUserMessage,
    String? lastAssistantMessage,
    bool different = false,
  }) async {
    try {
      if ((lastUserMessage == null || lastUserMessage.isEmpty) &&
          (lastAssistantMessage == null || lastAssistantMessage.isEmpty)) {
        return List<String>.from(starterSuggestions);
      }

      final user = lastUserMessage ?? '';
      final assistant = lastAssistantMessage ?? '';

      final llm = await _suggestWithLlm(
        user: user,
        assistant: assistant,
        different: different,
      );
      if (llm.isNotEmpty) return llm;

      final heuristic = _heuristicSuggestions(
        user: user,
        assistant: assistant,
        different: different,
      );
      if (heuristic.isNotEmpty) return heuristic;

      return _genericSuggestions(different: different);
    } catch (e) {
      debugPrint('FollowUpSuggestionService.suggest error: $e');
      return List<String>.from(starterSuggestions);
    }
  }

  Future<List<String>> _suggestWithLlm({
    required String user,
    required String assistant,
    required bool different,
  }) async {
    final clippedUser = _clip(user, 400);
    final clippedAssistant = _clip(assistant, 600);
    final diversity = different
        ? 'Suggest different angles than obvious follow-ups.'
        : 'Keep suggestions natural next steps.';
    final prompt =
        'Given this chat turn, suggest 3 short follow-up messages the user '
        'might tap to send next.\n'
        'User: $clippedUser\n'
        'Assistant: $clippedAssistant\n'
        '$diversity\n'
        'Return ONLY a JSON array of 3 short strings (max ~60 chars each). '
        'No numbering.';

    try {
      final raw = await ModelOrchestrator.instance.completeOnce(prompt: prompt);
      if (raw == null || raw.isEmpty) return const [];
      final parsed = parseSuggestions(raw);
      if (parsed.length < 2) return const [];

      return parsed;
    } catch (e) {
      debugPrint('FollowUpSuggestionService LLM failed: $e');

      return const [];
    }
  }

  static String _clip(String text, int max) {
    final trimmed = text.trim();
    if (trimmed.length <= max) return trimmed;

    return trimmed.substring(0, max);
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

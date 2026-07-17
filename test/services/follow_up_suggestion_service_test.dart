import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/follow_up_suggestion_service.dart';

void main() {
  group('FollowUpSuggestionService', () {
    test('parseSuggestions reads JSON array', () {
      final parsed = FollowUpSuggestionService.parseSuggestions(
        'Here you go: ["One?", "Two?", "Three?"]',
      );
      expect(parsed, ['One?', 'Two?', 'Three?']);
    });

    test('suggest returns starters when no context', () async {
      final suggestions = await FollowUpSuggestionService.instance.suggest(
        lastUserMessage: null,
        lastAssistantMessage: null,
      );
      expect(suggestions.length, 3);
      expect(suggestions.first, contains('screen'));
    });

    test('suggest returns weather follow-ups from context', () async {
      final suggestions = await FollowUpSuggestionService.instance.suggest(
        lastUserMessage: 'What is the weather?',
        lastAssistantMessage: 'It is rainy today.',
      );
      expect(suggestions.length, 3);
      expect(
        suggestions.any((s) => s.toLowerCase().contains('degree')),
        isTrue,
      );
    });

    test('reroll returns alternate weather follow-ups', () async {
      final first = await FollowUpSuggestionService.instance.suggest(
        lastUserMessage: 'weather',
        lastAssistantMessage: 'rainy',
      );
      final rerolled = await FollowUpSuggestionService.instance.suggest(
        lastUserMessage: 'weather',
        lastAssistantMessage: 'rainy',
        different: true,
      );
      expect(first, isNot(equals(rerolled)));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/suggestion_json_parser.dart';

void main() {
  group('SuggestionJsonParser', () {
    test('parseStringList extracts JSON array from prose', () {
      final parsed = SuggestionJsonParser.parseStringList(
        'Sure: ["One?", "Two?", "Three?"] thanks',
      );
      expect(parsed, ['One?', 'Two?', 'Three?']);
    });

    test('parseLabeledPrompts reads label/prompt objects', () {
      const raw = '''
[
  {"label": "Plan day", "prompt": "Help me plan my day:\\n\\n"},
  {"name": "Debug", "prompt": "Debug this:\\n"}
]
''';
      final parsed = SuggestionJsonParser.parseLabeledPrompts(raw);
      expect(parsed.length, 2);
      expect(parsed.first.label, 'Plan day');
      expect(parsed.first.prompt, contains('plan'));
      expect(parsed[1].label, 'Debug');
    });

    test('parsePresetDrafts reads preset fields', () {
      const raw = '''
[
  {
    "name": "Meal prep",
    "prompt": "Create a meal plan for:",
    "description": "Weekly meals",
    "category": "Productivity"
  }
]
''';
      final parsed = SuggestionJsonParser.parsePresetDrafts(raw);
      expect(parsed, hasLength(1));
      expect(parsed.first.name, 'Meal prep');
      expect(parsed.first.category, 'Productivity');
    });
  });
}

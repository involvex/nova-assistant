import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/prompt_presets_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PromptPresetsService.reset();
    await PromptPresetsService.instance.initialize();
  });

  tearDown(PromptPresetsService.reset);

  group('PromptPresetsService.emptyStateStarters', () {
    test('returns Summarize Plan Debug Learn labels by default', () {
      final starters = PromptPresetsService.instance.emptyStateStarters;

      expect(starters.map((s) => s.label).toList(), [
        'Summarize',
        'Plan',
        'Debug',
        'Learn',
      ]);
      for (final starter in starters) {
        expect(starter.prompt, isNotEmpty);
      }
    });
  });

  group('PromptPresetsService.contextualEmptyStateStarters', () {
    test('coder role prefers Debug and Explain Code', () {
      final starters = PromptPresetsService.instance
          .contextualEmptyStateStarters(
            const PromptStarterContext(roleName: 'coder', hourOfDay: 14),
          );

      final labels = starters.map((s) => s.label).toList();
      expect(labels.first, 'Debug');
      expect(labels, contains('Explain Code'));
    });

    test('morning boosts Plan to the front for helpful role', () {
      final starters = PromptPresetsService.instance
          .contextualEmptyStateStarters(
            const PromptStarterContext(roleName: 'helpful', hourOfDay: 8),
          );

      expect(starters.first.label, 'Plan');
    });

    test('image gen inserts Generate Image chip', () {
      final starters = PromptPresetsService.instance
          .contextualEmptyStateStarters(
            const PromptStarterContext(
              roleName: 'helpful',
              hourOfDay: 14,
              hasImageGen: true,
            ),
          );

      expect(starters.first.label, 'Generate Image');
      expect(starters.first.prompt.toLowerCase(), contains('image'));
    });
  });
}

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
    test('returns Summarize Plan Debug Learn labels', () {
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
}

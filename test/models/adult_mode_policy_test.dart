import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';

void main() {
  group('AdultModePolicy', () {
    test('prefsKey is stable', () {
      expect(AdultModePolicy.prefsKey, 'settings_adult_mode');
    });

    test('full suffix mentions adult topics and legality', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: false);
      expect(s.toLowerCase(), contains('adult'));
      expect(s.toLowerCase(), contains('illegal'));
      expect(s.length, lessThanOrEqualTo(400));
    });

    test('compact suffix is short', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: true);
      expect(s.length, lessThanOrEqualTo(180));
      expect(s.toLowerCase(), contains('adult'));
    });
  });
}

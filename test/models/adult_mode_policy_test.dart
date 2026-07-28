import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';

void main() {
  group('AdultModePolicy', () {
    test('prefsKey is stable', () {
      expect(AdultModePolicy.prefsKey, 'settings_adult_mode');
    });

    test(
      'full lead allows health and adult; refuses minors and crime how-tos',
      () {
        final s = AdultModePolicy.systemPromptLead(compact: false);
        expect(s.toLowerCase(), contains('health'));
        expect(s.toLowerCase(), contains('doctor'));
        expect(s.toLowerCase(), contains('minors'));
        expect(s.toLowerCase(), contains('crime'));
        expect(s.toLowerCase(), contains('do not bring up'));
        expect(s.length, lessThanOrEqualTo(900));
      },
    );

    test('compact lead stays short and covers health + refusals', () {
      final s = AdultModePolicy.systemPromptLead(compact: true);
      expect(s.length, lessThanOrEqualTo(320));
      expect(s.toLowerCase(), contains('health'));
      expect(s.toLowerCase(), contains('minors'));
      expect(s.toLowerCase(), contains('crime'));
    });

    test('full suffix reminds direct answers and refusal floor', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: false);
      expect(s.toLowerCase(), contains('health'));
      expect(s.toLowerCase(), contains('minors'));
      expect(s.length, lessThanOrEqualTo(220));
    });

    test('compact suffix is short', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: true);
      expect(s.length, lessThanOrEqualTo(120));
      expect(s.toLowerCase(), contains('minors'));
    });
  });
}

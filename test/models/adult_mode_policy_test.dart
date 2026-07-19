import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';

void main() {
  group('AdultModePolicy', () {
    test('prefsKey is stable', () {
      expect(AdultModePolicy.prefsKey, 'settings_adult_mode');
    });

    test('full lead forbids inventing safety policies', () {
      final s = AdultModePolicy.systemPromptLead(compact: false);
      expect(s.toLowerCase(), contains('adult mode'));
      expect(s.toLowerCase(), contains('on-device'));
      expect(s.toLowerCase(), contains('illegal'));
      expect(s.length, lessThanOrEqualTo(550));
    });

    test('compact lead stays short and forbids fake overrides', () {
      final s = AdultModePolicy.systemPromptLead(compact: true);
      expect(s.length, lessThanOrEqualTo(220));
      expect(s.toLowerCase(), contains('adult mode'));
      expect(s.toLowerCase(), contains('never invent'));
    });

    test('full suffix mentions adult topics and legality', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: false);
      expect(s.toLowerCase(), contains('adult'));
      expect(s.toLowerCase(), contains('illegal'));
      expect(s.length, lessThanOrEqualTo(400));
    });

    test('compact suffix is short', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: true);
      expect(s.length, lessThanOrEqualTo(120));
      expect(s.toLowerCase(), contains('adult'));
    });
  });
}

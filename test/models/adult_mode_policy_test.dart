import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';

void main() {
  group('AdultModePolicy', () {
    test('prefsKey is stable', () {
      expect(AdultModePolicy.prefsKey, 'settings_adult_mode');
    });

    test('full lead only applies when user asks; stays on topic otherwise', () {
      final s = AdultModePolicy.systemPromptLead(compact: false);
      expect(s.toLowerCase(), contains('adult mode'));
      expect(s.toLowerCase(), contains('only when'));
      expect(s.toLowerCase(), contains('do not bring up'));
      expect(s.toLowerCase(), contains('illegal'));
      expect(s.length, lessThanOrEqualTo(700));
    });

    test('compact lead stays short and topic-gated', () {
      final s = AdultModePolicy.systemPromptLead(compact: true);
      expect(s.length, lessThanOrEqualTo(280));
      expect(s.toLowerCase(), contains('only if'));
      expect(s.toLowerCase(), contains('do not mention'));
    });

    test('full suffix reminds not to volunteer adult topics', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: false);
      expect(s.toLowerCase(), contains('adult'));
      expect(s.toLowerCase(), contains('only when'));
      expect(s.length, lessThanOrEqualTo(200));
    });

    test('compact suffix is short', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: true);
      expect(s.length, lessThanOrEqualTo(120));
      expect(s.toLowerCase(), contains('adult'));
    });
  });
}

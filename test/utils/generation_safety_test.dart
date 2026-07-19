import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/utils/generation_safety.dart';

void main() {
  group('GenerationSafety', () {
    test('maxOutputCharsFor matches tiers', () {
      expect(GenerationSafety.maxOutputCharsFor(NovaModel.smollm), 2000);
      expect(GenerationSafety.maxOutputCharsFor(NovaModel.gemma3_1b), 4000);
      expect(GenerationSafety.maxOutputCharsFor(NovaModel.gemma4E2b), 6000);
      expect(GenerationSafety.maxOutputCharsForCustom(), 6000);
    });

    test('hasConsecutiveRepetition detects repeated window', () {
      const chunk = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP';
      expect(chunk.length, 52);
      final padded = chunk.padRight(80, 'x');
      final text = padded * 3;
      expect(GenerationSafety.hasConsecutiveRepetition(text), isTrue);
    });

    test('hasConsecutiveRepetition ignores short or unique text', () {
      expect(GenerationSafety.hasConsecutiveRepetition('hello world'), isFalse);
      // Unique non-repeating content longer than 3 windows.
      final unique = List.generate(300, (i) => 'w$i-').join();
      expect(GenerationSafety.hasConsecutiveRepetition(unique), isFalse);
    });

    test('safetyStopMessage for length and repetition', () {
      expect(GenerationSafety.safetyStopMessage('hi', 10), isNull);
      expect(
        GenerationSafety.safetyStopMessage('a' * 20, 10),
        contains('length limit'),
      );
      final chunk = ('repeat-me-please-' * 5).substring(0, 80);
      final looped = chunk * 3;
      expect(
        GenerationSafety.safetyStopMessage(looped, 100000),
        contains('repetition'),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/assistant_role.dart';

void main() {
  group('AssistantRole.compactSystemPrompt', () {
    test('all roles expose a single-line compact prompt', () {
      for (final role in AssistantRole.values) {
        final compact = role.compactSystemPrompt;
        expect(compact, isNotEmpty);
        expect(compact, isNot(contains('\n')));
        expect(compact.length, lessThan(80));
      }
    });

    test('coder compact prompt mentions programmer', () {
      expect(
        AssistantRole.coder.compactSystemPrompt.toLowerCase(),
        contains('programmer'),
      );
    });
  });
}

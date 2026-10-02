import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/availability_check_gate.dart';

void main() {
  group('shouldRunAvailabilityCheck', () {
    final DateTime now = DateTime(2026, 1, 1, 12);

    test('runs on first check and when forced', () {
      expect(
        shouldRunAvailabilityCheck(now: now, lastRun: null, force: false),
        isTrue,
      );
      expect(
        shouldRunAvailabilityCheck(now: now, lastRun: now, force: true),
        isTrue,
      );
    });

    test('skips rapid repeat checks from status bursts', () {
      expect(
        shouldRunAvailabilityCheck(
          now: now,
          lastRun: now.subtract(const Duration(seconds: 5)),
          force: false,
        ),
        isFalse,
      );
    });

    test('runs again after the interval', () {
      expect(
        shouldRunAvailabilityCheck(
          now: now,
          lastRun: now.subtract(const Duration(seconds: 25)),
          force: false,
        ),
        isTrue,
      );
    });
  });
}

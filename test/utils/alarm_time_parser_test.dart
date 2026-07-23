import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/alarm_time_parser.dart';

void main() {
  group('AlarmTimeParser', () {
    test('parses 7 AM chip text', () {
      final result = AlarmTimeParser.tryParse('Set an alarm for 7 AM');
      expect(result, isNotNull);
      expect(result!.hour, 7);
      expect(result.minute, 0);
    });

    test('parses 7:00 PM', () {
      final result = AlarmTimeParser.tryParse('Set an alarm for 7:00 PM');
      expect(result, isNotNull);
      expect(result!.hour, 19);
      expect(result.minute, 0);
    });

    test('parses 7pm without space', () {
      final result = AlarmTimeParser.tryParse('set alarm for 7pm');
      expect(result, isNotNull);
      expect(result!.hour, 19);
      expect(result.minute, 0);
    });

    test('parses 24-hour time', () {
      final result = AlarmTimeParser.tryParse('Set an alarm for 19:30');
      expect(result, isNotNull);
      expect(result!.hour, 19);
      expect(result.minute, 30);
    });

    test('returns null without alarm intent', () {
      expect(AlarmTimeParser.tryParse('What time is it?'), isNull);
    });

    test('returns null for alarm without time', () {
      expect(AlarmTimeParser.tryParse('Set an alarm'), isNull);
    });

    test('parses German Wecker um 19:00', () {
      final result = AlarmTimeParser.tryParse('stell einen Wecker um 19:00');
      expect(result, isNotNull);
      expect(result!.hour, 19);
      expect(result.minute, 0);
    });

    test('parses German Wecker auf 7 Uhr', () {
      final result = AlarmTimeParser.tryParse('Wecker auf 7 Uhr');
      expect(result, isNotNull);
      expect(result!.hour, 7);
      expect(result.minute, 0);
    });

    test('parses German timer for 10 minutes', () {
      final fixed = DateTime(2026, 7, 19, 16, 20);
      final result = AlarmTimeParser.tryParseTimer(
        'stell mir einen Timer für 10 Minuten',
        now: fixed,
      );
      expect(result, isNotNull);
      expect(result!.durationMinutes, 10);
      expect(result.hour, 16);
      expect(result.minute, 30);
    });

    test('parses English timer for 5 minutes', () {
      final fixed = DateTime(2026, 7, 19, 8, 0);
      final result = AlarmTimeParser.tryParseTimer(
        'set a timer for 5 minutes',
        now: fixed,
      );
      expect(result, isNotNull);
      expect(result!.durationMinutes, 5);
      expect(result.hour, 8);
      expect(result.minute, 5);
    });

    test('parses in N Minuten relative timer', () {
      final fixed = DateTime(2026, 7, 19, 12, 0);
      final result = AlarmTimeParser.tryParseTimer(
        'in 15 Minuten',
        now: fixed,
      );
      expect(result, isNotNull);
      expect(result!.durationMinutes, 15);
      expect(result.hour, 12);
      expect(result.minute, 15);
    });

    test('timer returns null without duration', () {
      expect(AlarmTimeParser.tryParseTimer('set a timer'), isNull);
    });
  });
}

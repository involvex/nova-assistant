import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/stream_paint_throttle.dart';

void main() {
  group('StreamPaintThrottle', () {
    test('paints the first chunk', () {
      final StreamPaintThrottle throttle = StreamPaintThrottle();
      final DateTime now = DateTime(2026, 1, 1);

      expect(throttle.shouldPaint(isFinal: false, now: now), isTrue);
    });

    test('coalesces rapid intermediate chunks', () {
      final StreamPaintThrottle throttle = StreamPaintThrottle();
      final DateTime start = DateTime(2026, 1, 1);

      expect(throttle.shouldPaint(isFinal: false, now: start), isTrue);
      expect(
        throttle.shouldPaint(
          isFinal: false,
          now: start.add(const Duration(milliseconds: 50)),
        ),
        isFalse,
      );
      expect(
        throttle.shouldPaint(
          isFinal: false,
          now: start.add(const Duration(milliseconds: 200)),
        ),
        isTrue,
      );
    });

    test('always paints the final chunk', () {
      final StreamPaintThrottle throttle = StreamPaintThrottle();
      final DateTime start = DateTime(2026, 1, 1);

      expect(throttle.shouldPaint(isFinal: false, now: start), isTrue);
      expect(
        throttle.shouldPaint(
          isFinal: true,
          now: start.add(const Duration(milliseconds: 10)),
        ),
        isTrue,
      );
    });
  });
}

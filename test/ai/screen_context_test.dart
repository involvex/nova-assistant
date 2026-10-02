import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/screen/screen_context.dart';
import 'package:nova_assistant/screen/screen_context_engine.dart';

void main() {
  group('ScreenContext', () {
    test('toJson carries package and timestamp', () {
      final ScreenContext context = ScreenContext(
        packageName: 'com.termux',
        visibleText: 'hello',
      );
      final Map<String, Object?> json = context.toJson();

      expect(json['packageName'], 'com.termux');
      expect(json['hasScreenshot'], isFalse);
      expect(context.hasText, isTrue);
      expect(context.hasVisual, isFalse);
    });
  });

  group('ScreenContextEngine', () {
    test('capture merges app + screenshot + ocr', () async {
      final ScreenContextEngine engine = ScreenContextEngine(
        screenshotProvider: () async => Uint8List.fromList(<int>[1, 2, 3]),
        activeAppProvider: () async =>
            (packageName: 'com.termux', activityName: 'TermuxActivity'),
        ocrProvider: (_) async => 'ocr hello',
      );

      final ScreenContext context = await engine.capture();

      expect(context.packageName, 'com.termux');
      expect(context.activityName, 'TermuxActivity');
      expect(context.ocrText, 'ocr hello');
      expect(context.hasVisual, isTrue);
    });

    test('capture degrades gracefully without providers', () async {
      final ScreenContextEngine engine = ScreenContextEngine(
        screenshotProvider: () async => null,
      );

      final ScreenContext context = await engine.capture();

      expect(context.hasVisual, isFalse);
      expect(context.packageName, isNull);
    });
  });
}

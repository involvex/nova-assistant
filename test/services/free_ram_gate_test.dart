import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/platform_adaptation_service.dart';

void main() {
  group('freeRamGateMessage', () {
    final service = PlatformAdaptationService.instance;

    test('blocks Gemma 4 when free RAM is below threshold on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final message = service.freeRamGateMessage(
        model: NovaModel.gemma4E2b,
        availMemMb: 1000,
      );
      expect(message, isNotNull);
      expect(message!, contains('Gemma 4 E2B'));
      expect(message, contains('1000 MB'));
    });

    test('allows Gemma 4 when enough free RAM', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        service.freeRamGateMessage(
          model: NovaModel.gemma4E2b,
          availMemMb: 2000,
        ),
        isNull,
      );
    });

    test('skips gate when availMem is unknown', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        service.freeRamGateMessage(
          model: NovaModel.gemma4E2b,
          availMemMb: null,
        ),
        isNull,
      );
    });

    test('no gate for SmolLM', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        service.freeRamGateMessage(model: NovaModel.smollm, availMemMb: 200),
        isNull,
      );
    });

    test('minFreeRamMbFor matches size tiers', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(service.minFreeRamMbFor(NovaModel.gemma4E2b), 1800);
      expect(service.minFreeRamMbFor(NovaModel.gemma3_1b), 700);
      expect(service.minFreeRamMbFor(NovaModel.smollm), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/platform_adaptation_service.dart';
import 'package:nova_assistant/models/model_info.dart';

void main() {
  group('PlatformCapabilities', () {
    test('current returns capabilities for current platform', () {
      final capabilities = PlatformCapabilities.current;

      // Test default target platform is Android — vision/thinking/FC/streaming
      // stay on; parallel sessions are capped off on Android for RAM safety.
      expect(capabilities.supportsVision, true);
      expect(capabilities.supportsThinking, true);
      expect(capabilities.supportsFunctionCalling, true);
      expect(capabilities.supportsStreaming, true);
      expect(capabilities.supportsParallelSessions, false);
      expect(capabilities.platformName, 'native');
    });

    test('supportsFeature returns correct value', () {
      final capabilities = PlatformCapabilities.current;

      expect(capabilities.supportsFeature(ModelFeature.vision), true);
      expect(capabilities.supportsFeature(ModelFeature.thinking), true);
      expect(capabilities.supportsFeature(ModelFeature.functionCalling), true);
    });

    test('getUnsupportedFeatures returns empty for native platform', () {
      final capabilities = PlatformCapabilities.current;
      final unsupported = capabilities.getUnsupportedFeatures(
        NovaModel.gemma4E2b,
      );

      expect(unsupported, isEmpty);
    });
  });

  group('PlatformAdaptationService', () {
    test('can be instantiated', () {
      final service = PlatformAdaptationService.instance;
      expect(service.capabilities, isNotNull);
    });

    test('getWebAdaptations returns empty for native platform', () {
      final service = PlatformAdaptationService.instance;
      final adaptations = service.getWebAdaptations(NovaModel.gemma4E2b);

      // On native platform, should return empty list
      expect(adaptations, isEmpty);
    });

    test('isModelCompatible returns true for all models on native', () {
      final service = PlatformAdaptationService.instance;

      expect(service.isModelCompatible(NovaModel.smollm), true);
      expect(service.isModelCompatible(NovaModel.fastvlm), true);
      expect(service.isModelCompatible(NovaModel.gemma3_1b), true);
      expect(service.isModelCompatible(NovaModel.gemma4E2b), true);
    });

    test('getInitializationParams returns correct params', () {
      final service = PlatformAdaptationService.instance;
      final params = service.getInitializationParams();

      expect(params.containsKey('maxDownloadRetries'), true);
      expect(params['maxDownloadRetries'], 10);
    });

    test('getBackendRecommendation returns gpu', () {
      final service = PlatformAdaptationService.instance;
      final recommendation = service.getBackendRecommendation();

      expect(recommendation, 'gpu');
    });

    test('getMemoryWarning returns null for small models', () {
      final service = PlatformAdaptationService.instance;
      final warning = service.getMemoryWarning(NovaModel.smollm);

      expect(warning, isNull);
    });

    test('getMemoryWarning returns warning for very large models', () {
      final service = PlatformAdaptationService.instance;
      final warning = service.getMemoryWarning(NovaModel.gemma4E2b);

      // Gemma 4 E2B is ~2400MB — warn so mid-range devices avoid LMK.
      expect(warning, isNotNull);
      expect(warning, contains('2400'));
      expect(warning!.toLowerCase(), contains('ram'));
    });

    test('maxParallelSessions is 1 on Android', () {
      final service = PlatformAdaptationService.instance;

      expect(service.maxParallelSessions, 1);
    });

    test('getPlatformError returns original error on native', () {
      final service = PlatformAdaptationService.instance;
      final error = service.getPlatformError('test error', NovaModel.gemma4E2b);

      expect(error, 'test error');
    });

    test('getWebStorageRecommendation returns correct mode', () {
      final service = PlatformAdaptationService.instance;

      // On native, should return 'native'
      expect(service.getWebStorageRecommendation(100), 'native');
      expect(service.getWebStorageRecommendation(3000), 'native');
    });

    test('getRecommendedWebModel returns appropriate model', () {
      final service = PlatformAdaptationService.instance;

      // On native, should return best model for requirements
      expect(
        service.getRecommendedWebModel(),
        anyOf(equals(NovaModel.smollm), equals(NovaModel.gemma4E2b)),
      );

      expect(
        service.getRecommendedWebModel(needsVision: true),
        anyOf(equals(NovaModel.fastvlm), equals(NovaModel.gemma4E2b)),
      );
    });
  });
}

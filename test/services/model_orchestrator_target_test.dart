import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/ai/bootstrap.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';

void main() {
  group('EffectiveTarget', () {
    test('isLocal reflects registry id prefix', () {
      const local = EffectiveTarget(
        label: 'Gemma 4 E2B',
        providerId: 'local-gemma',
      );
      const cloud = EffectiveTarget(
        label: 'OpenRouter',
        providerId: 'openrouter',
      );

      expect(local.isLocal, isTrue);
      expect(cloud.isLocal, isFalse);
    });
  });

  group('ModelOrchestrator.providerDisplayName', () {
    test('maps known provider ids', () {
      expect(ModelOrchestrator.providerDisplayName('openai'), 'Remote LAN');
      expect(ModelOrchestrator.providerDisplayName('openrouter'), 'OpenRouter');
      expect(ModelOrchestrator.providerDisplayName('groq'), 'Groq');
      expect(
        ModelOrchestrator.providerDisplayName('opencode-zen'),
        'Opencode Zen',
      );
      expect(
        ModelOrchestrator.providerDisplayName('kilo-gateway'),
        'Kilo Gateway',
      );
      expect(
        ModelOrchestrator.providerDisplayName('local-qwen'),
        'Qwen (local)',
      );
      expect(
        ModelOrchestrator.providerDisplayName('local-gemma'),
        'Gemma (local)',
      );
    });
  });

  group('ModelOrchestrator.predictEffectiveTarget', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      NovaBootstrap.resetForTesting();
      ModelOrchestrator.instance.preferredCloudProvider = null;
      ModelOrchestrator.instance.clearModelOverride();
    });

    tearDown(() {
      ModelOrchestrator.instance.preferredCloudProvider = null;
      ModelOrchestrator.instance.clearModelOverride();
    });

    test('falls back to local selection without NovaCore', () async {
      final EffectiveTarget target = await ModelOrchestrator.instance
          .predictEffectiveTarget(query: 'Hallo Nova');

      expect(target.isLocal, isTrue);
      expect(target.localModel, isNotNull);
      expect(target.label, target.localModel!.displayName);
    });

    test('forcePrimaryModel pins the heavy model', () async {
      final EffectiveTarget target = await ModelOrchestrator.instance
          .predictEffectiveTarget(query: 'Hallo Nova', forcePrimaryModel: true);

      expect(target.localModel, NovaModel.gemma4E2b);
      expect(target.label, 'Gemma 4 E2B');
    });

    test('pinned cloud provider targets its registry id', () async {
      ModelOrchestrator.instance.preferredCloudProvider = 'kilo-gateway';

      final EffectiveTarget target = await ModelOrchestrator.instance
          .predictEffectiveTarget(query: 'Hallo Nova');

      expect(target.isLocal, isFalse);
      expect(target.providerId, 'kilo-gateway');
      expect(target.label, 'Kilo Gateway');
      expect(target.localModel, isNull);
    });
  });
}

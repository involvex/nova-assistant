import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/ai/router/provider_strategy.dart';
import 'package:nova_assistant/ai/router/routing_candidates.dart';
import 'package:nova_assistant/ai/router/routing_context.dart';
import 'package:nova_assistant/ai/router/routing_preset.dart';
import 'package:nova_assistant/ai/router/smart_router.dart';
import 'package:nova_assistant/core/config/provider_config.dart';

const ProviderStrategy _strategy = ProviderStrategy(
  ProviderConfig(<String, String>{
    'simple': 'local-gemma',
    'coding': 'kilo-gateway',
    'vision': 'local-gemma',
    'automation': 'local-qwen',
    'fallback': 'kilo-gateway',
  }),
);

RoutingContext _ctx(
  Intent intent, {
  Map<String, bool> cloud = const <String, bool>{},
  Set<String> locals = const <String>{},
  String query = 'test',
  bool hasImage = false,
}) {
  return RoutingContext(
    query: query,
    intent: intent,
    hasImage: hasImage,
    installedLocalModels: locals,
    cloudAvailable: cloud,
  );
}

void main() {
  const SmartRouter router = SmartRouter();

  group('SmartRouter', () {
    test('device actions always stay local', () {
      final RoutingDecision tool = router.select(
        _ctx(Intent.tool, cloud: const <String, bool>{'kilo-gateway': true}),
        strategy: _strategy,
      );

      expect(tool.providerId.startsWith('local-'), isTrue);
      expect(tool.reasons, isNotEmpty);
    });

    test('cloud intent uses first configured cloud in strategy order', () {
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.cloud,
          cloud: const <String, bool>{'openrouter': true, 'groq': true},
        ),
        strategy: _strategy,
      );

      // Strategy coding=kilo (unconfigured) → fallback kilo (unconfigured)
      // → preference order kilo, openrouter → openrouter.
      expect(decision.providerId, 'openrouter');
    });

    test('cloud intent prefers kilo when configured', () {
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.cloud,
          cloud: const <String, bool>{'kilo-gateway': true, 'openrouter': true},
        ),
        strategy: _strategy,
      );

      expect(decision.providerId, 'kilo-gateway');
    });

    test('cloud intent without any token falls back local with reason', () {
      final RoutingDecision decision = router.select(
        _ctx(Intent.cloud),
        strategy: _strategy,
      );

      expect(decision.providerId, 'local-gemma');
      expect(
        decision.reasons.any((String r) => r.contains('no cloud token')),
        isTrue,
      );
    });

    test('vision stays local when a vision model is installed', () {
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.vision,
          hasImage: true,
          locals: <String>{'gemma4E2b'},
          cloud: const <String, bool>{'kilo-gateway': true},
        ),
        strategy: _strategy,
      );

      expect(decision.providerId, 'local-gemma');
    });

    test('vision without local vision model uses configured cloud', () {
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.vision,
          hasImage: true,
          locals: <String>{'smollm'},
          cloud: const <String, bool>{'groq': true},
        ),
        strategy: _strategy,
      );

      expect(decision.providerId, 'groq');
    });

    test('heavy pasted content escalates to cloud when configured', () {
      final String heavy = List<String>.filled(80, 'lorem ipsum dolor ').join();
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.local,
          query: heavy,
          cloud: const <String, bool>{'kilo-gateway': true},
        ),
        strategy: _strategy,
      );

      expect(decision.intent, Intent.cloud);
      expect(decision.providerId, 'kilo-gateway');
    });

    test('plain chat stays local', () {
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.local,
          query: 'Wie spät ist es?',
          cloud: const <String, bool>{'kilo-gateway': true},
        ),
        strategy: _strategy,
      );

      expect(decision.providerId, 'local-gemma');
    });
  });

  group('SmartRouter presets', () {
    test('free preset picks kilo-auto/free when configured', () {
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.cloud,
          cloud: const <String, bool>{'kilo-gateway': true, 'openrouter': true},
        ),
        strategy: _strategy,
        preset: RoutingPreset.free,
      );

      expect(decision.providerId, 'kilo-gateway');
      expect(decision.modelId, 'kilo-auto/free');
    });

    test('balanced preset picks kilo-auto/efficient', () {
      final RoutingDecision decision = router.select(
        _ctx(Intent.cloud, cloud: const <String, bool>{'kilo-gateway': true}),
        strategy: _strategy,
        preset: RoutingPreset.balanced,
      );

      expect(decision.providerId, 'kilo-gateway');
      expect(decision.modelId, 'kilo-auto/efficient');
    });

    test('max preset picks opus on openrouter', () {
      final RoutingDecision decision = router.select(
        _ctx(
          Intent.cloud,
          cloud: const <String, bool>{'kilo-gateway': true, 'openrouter': true},
        ),
        strategy: _strategy,
        preset: RoutingPreset.max,
      );

      expect(decision.providerId, 'openrouter');
      expect(decision.modelId, 'anthropic/claude-opus-4.5');
    });

    test('toggled-off provider is skipped with reason', () {
      final RoutingDecision decision = router.select(
        RoutingContext(
          query: 'Analysiere diese APK',
          intent: Intent.cloud,
          cloudAvailable: const <String, bool>{
            'kilo-gateway': true,
            'openrouter': true,
          },
          enabledCandidates: <String>{RoutingCandidates.cloudId('openrouter')},
        ),
        strategy: _strategy,
      );

      expect(decision.providerId, 'openrouter');
      expect(
        decision.reasons.any((String r) => r.contains('toggled off')),
        isTrue,
      );
    });

    test('vision with toggled-off local vision uses cloud', () {
      final RoutingDecision decision = router.select(
        RoutingContext(
          query: 'Was sehe ich?',
          intent: Intent.vision,
          hasImage: true,
          installedLocalModels: <String>{'gemma4E2b'},
          cloudAvailable: const <String, bool>{'groq': true},
          enabledCandidates: <String>{
            RoutingCandidates.localId('smollm'),
            RoutingCandidates.cloudId('groq'),
          },
        ),
        strategy: _strategy,
      );

      expect(decision.providerId, 'groq');
    });
  });

  group('SmartRouter.firstAvailableCloud', () {
    test('respects strategy-first order and skips locals', () {
      expect(
        SmartRouter.firstAvailableCloud(
          const <String, bool>{'openrouter': true},
          extraFirst: const <String>['kilo-gateway', 'local-gemma'],
        ),
        'openrouter',
      );
      expect(SmartRouter.firstAvailableCloud(const <String, bool>{}), isNull);
    });
  });
}

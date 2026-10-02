import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/ai/router/routing_candidates.dart';
import 'package:nova_assistant/ai/router/routing_preset.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('RoutingCandidates', () {
    test('missing entry means all enabled', () async {
      expect(await RoutingCandidates.loadIds(), isNull);
      expect(RoutingCandidates.isEnabled(null, 'cloud:kilo-gateway'), isTrue);
      expect(RoutingCandidates.enabledLocalModels(null), isNull);
    });

    test('round-trips explicit toggles', () async {
      await RoutingCandidates.saveIds(<String>{
        RoutingCandidates.localId('smollm'),
        RoutingCandidates.cloudId('kilo-gateway'),
      });

      final Set<String>? loaded = await RoutingCandidates.loadIds();

      expect(loaded, isNotNull);
      expect(RoutingCandidates.isEnabled(loaded, 'cloud:kilo-gateway'), isTrue);
      expect(RoutingCandidates.isEnabled(loaded, 'cloud:openrouter'), isFalse);
      expect(RoutingCandidates.enabledLocalModels(loaded), <String>{'smollm'});
    });
  });

  group('RoutingPreset', () {
    test('tables carry verified provider/model pairs', () {
      final Map<RoutingPreset, List<List<String?>>> chains = {
        for (final RoutingPreset preset in RoutingPreset.values)
          preset: [
            for (final CloudTarget target in presetTargets(preset))
              <String?>[target.providerId, target.modelId],
          ],
      };

      expect(chains[RoutingPreset.free]!.first, <String?>[
        'kilo-gateway',
        'kilo-auto/free',
      ]);
      expect(chains[RoutingPreset.max]!.first, <String?>[
        'openrouter',
        'anthropic/claude-opus-4.5',
      ]);
      for (final List<List<String?>> chain in chains.values) {
        expect(chain, isNotEmpty);
        for (final List<String?> target in chain) {
          expect(target[0], isNotEmpty);
          expect(target[1], isNotNull);
        }
      }
    });

    test('defaults to free and round-trips', () async {
      expect(await RoutingPresetStore.load(), RoutingPreset.free);

      await RoutingPresetStore.save(RoutingPreset.max);
      expect(await RoutingPresetStore.load(), RoutingPreset.max);

      await RoutingPresetStore.save(RoutingPreset.balanced);
      expect(await RoutingPresetStore.load(), RoutingPreset.balanced);
    });
  });
}

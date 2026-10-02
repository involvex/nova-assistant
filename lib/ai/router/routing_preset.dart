import 'package:shared_preferences/shared_preferences.dart';

/// Smart cloud routing setups: which (provider, model) chain auto-routed
/// cloud turns try, in order. Model ids are verified live against each
/// provider's `/models` endpoint (never guessed).
enum RoutingPreset { free, balanced, max }

/// One ordered cloud target. A null [modelId] means "provider default"
/// (the model configured in settings); presets set explicit ids.
class CloudTarget {
  const CloudTarget(this.providerId, [this.modelId]);

  final String providerId;
  final String? modelId;
}

/// Ordered (provider, model) chains per preset.
List<CloudTarget> presetTargets(RoutingPreset preset) {
  switch (preset) {
    case RoutingPreset.free:
      // No credits needed anywhere in this chain.
      return const <CloudTarget>[
        CloudTarget('kilo-gateway', 'kilo-auto/free'),
        CloudTarget('openrouter', 'qwen/qwen3.8-27b:free'),
      ];
    case RoutingPreset.balanced:
      return const <CloudTarget>[
        CloudTarget('kilo-gateway', 'kilo-auto/efficient'),
        CloudTarget('openrouter', 'anthropic/claude-sonnet-4'),
        CloudTarget('groq', 'llama-3.3-70b-versatile'),
      ];
    case RoutingPreset.max:
      return const <CloudTarget>[
        CloudTarget('openrouter', 'anthropic/claude-opus-4.5'),
        CloudTarget('kilo-gateway', 'kilo-auto/efficient'),
        CloudTarget('groq', 'llama-3.3-70b-versatile'),
      ];
  }
}

/// Persistence for the active preset. Default is [RoutingPreset.free] —
/// auto routing must never spend money unasked.
class RoutingPresetStore {
  const RoutingPresetStore._();

  static const String prefsKey = 'settings_routing_preset';

  static Future<RoutingPreset> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefsKey);
      for (final RoutingPreset preset in RoutingPreset.values) {
        if (preset.name == raw) {
          return preset;
        }
      }
    } catch (_) {
      // Fall through to the safe default.
    }

    return RoutingPreset.free;
  }

  static Future<void> save(RoutingPreset preset) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, preset.name);
  }
}

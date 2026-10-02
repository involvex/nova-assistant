import 'package:flutter/foundation.dart';
import 'package:nova_assistant/ai/providers/ai_provider.dart';

/// Central registry. Providers register by id, Nova Core resolves by id.
/// New providers require only a new [AIProvider] class + registration,
/// no core changes (Phase-7 `providers.yaml` builds on this).
class ProviderRegistry {
  ProviderRegistry._();

  static final Map<String, AIProvider> _providers = <String, AIProvider>{};

  static void register(AIProvider provider) {
    _providers[provider.id] = provider;
  }

  static void registerAll(Iterable<AIProvider> providers) {
    for (final AIProvider provider in providers) {
      register(provider);
    }
  }

  static AIProvider get(String id) {
    final AIProvider? provider = _providers[id];
    if (provider == null) {
      throw StateError('No AIProvider registered for id "$id"');
    }

    return provider;
  }

  static AIProvider? tryGet(String id) {
    return _providers[id];
  }

  static List<String> get ids => List<String>.unmodifiable(_providers.keys);

  static bool get isEmpty => _providers.isEmpty;

  @visibleForTesting
  static void clearForTesting() {
    _providers.clear();
  }
}

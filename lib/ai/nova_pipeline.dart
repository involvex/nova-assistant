/// Feature flag + delegation rule for optional smart routing.
///
/// Local-first is always the default: without the flag every turn runs
/// on-device. When the user enables smart routing, NovaCore decides per
/// task whether a request goes local or to a configured cloud provider.
///
/// Single source of truth for the prefs key so settings UI, orchestrator
/// and tests can never drift apart.
class NovaPipeline {
  const NovaPipeline._();

  /// Settings toggle: opt-in smart routing via `NovaCore`.
  static const String enabledPrefsKey = 'settings_novacore_pipeline';

  /// Gradual rollout rule: only true cloud providers delegate.
  /// Local providers (and offline-gated fallbacks) always stay on the
  /// legacy on-device path — never worse than today.
  static bool shouldDelegate({
    required bool pipelineEnabled,
    required String providerId,
  }) {
    if (!pipelineEnabled) {
      return false;
    }
    if (providerId.isEmpty || providerId.startsWith('local-')) {
      return false;
    }

    return true;
  }
}

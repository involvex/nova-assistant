/// Cached cloud-token presence (`providerId → token configured`).
///
/// Secure-storage reads are slow in failure cases (5s timeout each), so
/// per-turn routing must never read tokens directly. `NovaBootstrap`
/// snapshots availability at startup and on settings refresh; the smart
/// router reads this cache synchronously. Empty (or all-false) means
/// local-first — routing silently stays on-device.
class CloudAvailability {
  CloudAvailability._();

  static Map<String, bool> _available = const <String, bool>{};

  static Map<String, bool> get current => _available;

  static void update(Map<String, bool> available) {
    _available = Map<String, bool>.unmodifiable(available);
  }

  static void resetForTesting() {
    _available = const <String, bool>{};
  }
}

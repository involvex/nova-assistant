import 'package:connectivity_plus/connectivity_plus.dart';

/// Offline-first gate. No network -> local providers only.
/// Injectable [checkOnline] keeps this unit-testable without plugins.
class OfflineFirstPolicy {
  OfflineFirstPolicy({Future<bool> Function()? checkOnline})
    : _checkOnline = checkOnline ?? _defaultCheck;

  final Future<bool> Function() _checkOnline;

  bool _lastOnline = true;

  bool get lastOnline => _lastOnline;

  static Future<bool> _defaultCheck() async {
    try {
      final List<ConnectivityResult> results = await Connectivity()
          .checkConnectivity();
      if (results.isEmpty) {
        return false;
      }

      return !results.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  /// Returns true when cloud providers may be used.
  Future<bool> isOnline() async {
    try {
      _lastOnline = await _checkOnline();
    } catch (_) {
      _lastOnline = true;
    }

    return _lastOnline;
  }

  /// Forces [providerId] to a local fallback when offline.
  Future<String> gateProvider(String providerId) async {
    final bool online = await isOnline();
    if (online) {
      return providerId;
    }
    if (providerId.startsWith('local-')) {
      return providerId;
    }

    return 'local-gemma';
  }
}

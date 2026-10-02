import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Routing-candidate toggles from the model selector.
/// ID scheme: `local:<NovaModel.name>`, `custom:<id>`, `cloud:<providerId>`.
/// A missing prefs entry (never saved) means everything is enabled —
/// toggles are purely opt-out, so existing installs keep working.
class RoutingCandidates {
  const RoutingCandidates._();

  static const String prefsKey = 'settings_routing_candidates';

  static String localId(String modelName) => 'local:$modelName';

  static String customId(String id) => 'custom:$id';

  static String cloudId(String providerId) => 'cloud:$providerId';

  /// Full enabled id set, or null when never saved (all enabled).
  /// Never throws — routing must not die on a prefs failure.
  static Future<Set<String>?> loadIds() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? stored = prefs.getStringList(prefsKey);
      if (stored == null) {
        return null;
      }

      return Set<String>.unmodifiable(stored);
    } catch (e) {
      debugPrint('RoutingCandidates.loadIds failed: $e');

      return null;
    }
  }

  static Future<void> saveIds(Set<String> ids) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, ids.toList());
    } catch (e) {
      debugPrint('RoutingCandidates.saveIds failed: $e');
    }
  }

  /// Pure check used by the router: null set = all enabled.
  static bool isEnabled(Set<String>? enabled, String id) {
    return enabled == null || enabled.contains(id);
  }

  /// Enabled local model names, or null when all are enabled.
  static Set<String>? enabledLocalModels(Set<String>? enabled) {
    if (enabled == null) {
      return null;
    }
    final Set<String> names = <String>{};
    for (final String id in enabled) {
      if (id.startsWith('local:')) {
        names.add(id.substring('local:'.length));
      }
    }

    return names;
  }
}

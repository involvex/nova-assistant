import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional Shizuku / root power-user helpers (force-stop, app info, battery).
class ShizukuService {
  static ShizukuService? _instance;
  static ShizukuService get instance => _instance ??= ShizukuService._();

  ShizukuService._();

  static const _channel = MethodChannel('dev.nova.assistant/shizuku');
  static const _prefsAdvanced = 'settings_shizuku_advanced';
  static const _prefsAllowForceStop = 'settings_shizuku_allow_force_stop';

  bool _advancedEnabled = false;
  bool _allowAssistantForceStop = false;
  bool _loaded = false;

  /// UI must set this to show a confirm dialog before force-stop.
  Future<bool> Function(String packageName)? confirmationHandler;

  bool get advancedEnabled => _advancedEnabled;
  bool get allowAssistantForceStop => _allowAssistantForceStop;

  /// Whether [force_stop_app] should be exposed to the model.
  bool get shouldExposeForceStopTool =>
      _advancedEnabled && _allowAssistantForceStop;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _advancedEnabled = prefs.getBool(_prefsAdvanced) ?? false;
    _allowAssistantForceStop = prefs.getBool(_prefsAllowForceStop) ?? false;
    _loaded = true;
  }

  Future<void> setAdvancedEnabled(bool value) async {
    _advancedEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAdvanced, value);
  }

  Future<void> setAllowAssistantForceStop(bool value) async {
    _allowAssistantForceStop = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAllowForceStop, value);
  }

  Future<Map<String, dynamic>> status() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('status');
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } on MissingPluginException {
      return {
        'ready': false,
        'binderAlive': false,
        'permissionGranted': false,
        'suAvailable': false,
        'error': 'Shizuku channel unavailable on this platform',
      };
    } catch (e) {
      debugPrint('ShizukuService.status error: $e');
    }

    return {'ready': false, 'error': 'status failed'};
  }

  Future<Map<String, dynamic>> requestPermission() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('requestPermission');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }

    return {'success': false, 'error': 'request failed'};
  }

  Future<Map<String, dynamic>> openAppInfo(String packageName) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('openAppInfo', {
        'package': packageName,
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }

    return {'success': false, 'error': 'openAppInfo failed'};
  }

  Future<Map<String, dynamic>> openBatterySettings() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('openBatterySettings');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }

    return {'success': false, 'error': 'openBatterySettings failed'};
  }

  /// Confirms with the user (when a handler is set), then force-stops [package].
  Future<Map<String, dynamic>> forceStopApp(String package) async {
    await ensureLoaded();
    if (!_advancedEnabled) {
      return {
        'success': false,
        'error': 'Enable Settings → Advanced (Shizuku) first.',
      };
    }
    if (!_allowAssistantForceStop) {
      return {
        'success': false,
        'error':
            'Enable “Allow assistant to force-stop apps” in Advanced settings.',
      };
    }

    final handler = confirmationHandler;
    if (handler == null) {
      return {
        'success': false,
        'error': 'Force-stop confirmation UI is not available.',
      };
    }

    final confirmed = await handler(package);
    if (!confirmed) {
      return {'success': false, 'error': 'User cancelled force-stop'};
    }

    try {
      final raw = await _channel.invokeMethod<dynamic>('forceStop', {
        'package': package,
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }

    return {'success': false, 'error': 'force-stop failed'};
  }
}

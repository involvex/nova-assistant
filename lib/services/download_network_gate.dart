import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gates large Hub / network model downloads on Wi‑Fi vs cellular.
class DownloadNetworkGate {
  DownloadNetworkGate._();

  static DownloadNetworkGate? _instance;
  static DownloadNetworkGate get instance =>
      _instance ??= DownloadNetworkGate._();

  static const wifiOnlyPrefsKey = 'settings_wifi_only_downloads';

  final Connectivity _connectivity = Connectivity();

  /// Whether downloads are restricted to Wi‑Fi / ethernet only.
  Future<bool> isWifiOnlyEnabled() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(wifiOnlyPrefsKey) ?? false;
  }

  Future<void> setWifiOnlyEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(wifiOnlyPrefsKey, enabled);
  }

  /// True when the active link is cellular (or unknown mobile).
  Future<bool> isOnCellular() async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty) return false;
    if (results.contains(ConnectivityResult.none)) return false;
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return false;
    }

    return results.contains(ConnectivityResult.mobile);
  }

  Future<bool> hasNetwork() async {
    final results = await _connectivity.checkConnectivity();

    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  /// Returns true when the caller may proceed with a download.
  ///
  /// Shows a confirm dialog on cellular when Wi‑Fi-only is off; blocks when
  /// Wi‑Fi-only is on and the device is on cellular / offline.
  Future<bool> confirmDownloadAllowed(
    BuildContext context, {
    String? sizeHint,
  }) async {
    if (!await hasNetwork()) {
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No network'),
          content: const Text(
            'Connect to the internet before downloading a model.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return false;
    }

    final onCellular = await isOnCellular();
    if (!onCellular) return true;

    final wifiOnly = await isWifiOnlyEnabled();
    if (!context.mounted) return false;

    if (wifiOnly) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Wi‑Fi required'),
          content: Text(
            'Wi‑Fi only downloads is on. Connect to Wi‑Fi to download'
            '${sizeHint != null ? ' ($sizeHint)' : ''}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download on cellular?'),
        content: Text(
          'You are on a mobile network. Model files can be several GB'
          '${sizeHint != null ? ' ($sizeHint)' : ''}. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download anyway'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  @visibleForTesting
  static void reset() {
    _instance = null;
  }
}

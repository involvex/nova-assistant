import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenshotService {
  static const _channel = MethodChannel('dev.nova.assistant/screenshot');

  static ScreenshotService? _instance;
  static ScreenshotService get instance => _instance ??= ScreenshotService._();

  ScreenshotService._();

  Uint8List? _cachedScreenshot;
  DateTime? _lastCapture;

  Uint8List? get cachedScreenshot => _cachedScreenshot;

  Future<Uint8List?> getLatestScreenshot() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'getLatestScreenshot',
      );
      if (result != null && result.isNotEmpty) {
        _cachedScreenshot = result;
        _lastCapture = DateTime.now();
      }

      return result;
    } on PlatformException catch (e) {
      debugPrint('ScreenshotService: PlatformException — ${e.message}');

      return null;
    } on MissingPluginException {
      debugPrint(
        'ScreenshotService: Screenshot channel not available (not launched via MainActivity)',
      );

      return null;
    } catch (e) {
      debugPrint('ScreenshotService: failed to get screenshot — $e');

      return null;
    }
  }

  Future<bool> isCapturing() async {
    try {
      return await _channel.invokeMethod<bool>('isCapturing') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestCapture() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestCapture');

      return result ?? false;
    } on MissingPluginException {
      debugPrint(
        'ScreenshotService: Capture not available — channel not registered',
      );

      return false;
    } catch (_) {
      return false;
    }
  }

  bool get hasRecentCapture {
    if (_cachedScreenshot == null || _lastCapture == null) return false;

    return DateTime.now().difference(_lastCapture!).inSeconds < 5;
  }

  void clearCache() {
    _cachedScreenshot = null;
    _lastCapture = null;
  }
}

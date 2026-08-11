import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OverlayService {
  static const _channel = MethodChannel('dev.nova.assistant/overlay');

  static OverlayService? _instance;
  static OverlayService get instance => _instance ??= OverlayService._();

  OverlayService._();

  Future<String> getLaunchMode() async {
    try {
      final mode = await _channel.invokeMethod<String>('getLaunchMode');

      return mode ?? 'full';
    } on MissingPluginException {
      debugPrint('OverlayService: Overlay channel not available');

      return 'full';
    } catch (e) {
      debugPrint('OverlayService: failed to get launch mode — $e');

      return 'full';
    }
  }

  Future<void> hideForCapture() async {
    try {
      await _channel.invokeMethod<void>('hideForCapture');
    } catch (e) {
      debugPrint('OverlayService: hideForCapture failed — $e');
    }
  }

  Future<void> showAfterCapture() async {
    try {
      await _channel.invokeMethod<void>('showAfterCapture');
    } catch (e) {
      debugPrint('OverlayService: showAfterCapture failed — $e');
    }
  }

  Future<void> expandToFullApp() async {
    try {
      await _channel.invokeMethod<void>('expandToFullApp');
    } catch (e) {
      debugPrint('OverlayService: expandToFullApp failed — $e');
    }
  }
}

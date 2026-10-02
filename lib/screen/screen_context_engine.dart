// ignore_for_file: prefer_initializing_formals
import 'dart:typed_data';

import 'package:nova_assistant/platform/screenshot_service.dart';
import 'package:nova_assistant/screen/screen_context.dart';

/// Active-app info provider. Android side exposes package/activity via
/// MethodChannel (TODO native); default returns nulls (screenshot-only mode).
typedef ActiveAppProvider =
    Future<({String? packageName, String? activityName})> Function();

/// OCR provider. MLKit/Tesseract lands here later; default is null (no OCR).
typedef OcrProvider = Future<String?> Function(Uint8List imageBytes);

/// Screenshot bytes provider. Default uses [ScreenshotService]; tests inject.
typedef ScreenshotProvider = Future<Uint8List?> Function();

/// Builds [ScreenContext] from screenshot + active app + OCR.
/// Vision queries call [capture] automatically via [NovaCore].
class ScreenContextEngine {
  ScreenContextEngine({
    ScreenshotProvider? screenshotProvider,
    ActiveAppProvider? activeAppProvider,
    OcrProvider? ocrProvider,
  }) : _screenshotProvider =
           screenshotProvider ??
           (() => ScreenshotService.instance.getLatestScreenshot()),
       _activeAppProvider = activeAppProvider,
       _ocrProvider = ocrProvider;

  final ScreenshotProvider _screenshotProvider;
  final ActiveAppProvider? _activeAppProvider;
  final OcrProvider? _ocrProvider;

  ScreenContext lastContext = ScreenContext();

  Future<ScreenContext> capture({bool includeScreenshot = true}) async {
    String? packageName;
    String? activityName;
    if (_activeAppProvider != null) {
      try {
        final ({String? activityName, String? packageName}) app =
            await _activeAppProvider();
        packageName = app.packageName;
        activityName = app.activityName;
      } catch (_) {
        packageName = null;
      }
    }

    Uint8List? bytes;
    if (includeScreenshot) {
      try {
        bytes = await _screenshotProvider();
      } catch (_) {
        bytes = null;
      }
    }

    String? ocrText;
    final OcrProvider? ocr = _ocrProvider;
    if (bytes != null && bytes.isNotEmpty && ocr != null) {
      try {
        ocrText = await ocr(bytes);
      } catch (_) {
        ocrText = null;
      }
    }

    lastContext = ScreenContext(
      packageName: packageName,
      activityName: activityName,
      ocrText: ocrText,
      screenshotBytes: bytes,
    );

    return lastContext;
  }
}

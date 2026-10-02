import 'dart:typed_data';

/// Structured screen awareness payload. Vision requests always carry this.
class ScreenContext {
  ScreenContext({
    this.packageName,
    this.activityName,
    this.visibleText,
    this.ocrText,
    this.screenshotBytes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String? packageName;
  final String? activityName;
  final String? visibleText;
  final String? ocrText;
  final Uint8List? screenshotBytes;
  final DateTime timestamp;

  bool get hasVisual => screenshotBytes != null && screenshotBytes!.isNotEmpty;

  bool get hasText =>
      (visibleText != null && visibleText!.isNotEmpty) ||
      (ocrText != null && ocrText!.isNotEmpty);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'packageName': packageName,
      'activityName': activityName,
      'visibleText': visibleText,
      'ocrText': ocrText,
      'hasScreenshot': hasVisual,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

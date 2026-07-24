import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Shrinks screenshots / photos before vision inference so image tokens
/// fit inside small on-device KV windows (e.g. Gemma 4 @ 4096).
class VisionImagePrep {
  const VisionImagePrep._();

  /// Max longest edge in pixels for model input.
  static const defaultMaxSide = 768;

  /// Skip re-encode when already small enough (bytes + dimensions).
  static const _skipIfUnderBytes = 180 * 1024;

  /// Returns a PNG (or the original bytes if already small).
  static Future<Uint8List> prepareForInference(
    Uint8List bytes, {
    int maxSide = defaultMaxSide,
  }) async {
    if (bytes.isEmpty) return bytes;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;

      if (w <= maxSide &&
          h <= maxSide &&
          bytes.lengthInBytes <= _skipIfUnderBytes) {
        image.dispose();

        return bytes;
      }

      image.dispose();

      final scaledCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: w >= h ? maxSide : null,
        targetHeight: h > w ? maxSide : null,
      );
      final scaledFrame = await scaledCodec.getNextFrame();
      final scaled = scaledFrame.image;
      final outW = scaled.width;
      final outH = scaled.height;
      final png = await scaled.toByteData(format: ui.ImageByteFormat.png);
      scaled.dispose();

      if (png == null) return bytes;

      final out = png.buffer.asUint8List();
      debugPrint(
        'VisionImagePrep: ${w}x$h (${bytes.lengthInBytes}B) → '
        '${outW}x$outH (${out.lengthInBytes}B)',
      );

      return out;
    } catch (e) {
      debugPrint('VisionImagePrep failed, using original: $e');

      return bytes;
    }
  }
}

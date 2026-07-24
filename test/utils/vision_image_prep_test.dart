import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/vision_image_prep.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisionImagePrep', () {
    test('returns empty input unchanged', () async {
      final out = await VisionImagePrep.prepareForInference(Uint8List(0));
      expect(out, isEmpty);
    });

    test('downscales a large synthetic image', () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFF112233), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1600, 2400);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      expect(png, isNotNull);

      final input = png!.buffer.asUint8List();
      final out = await VisionImagePrep.prepareForInference(
        input,
        maxSide: 768,
      );

      final codec = await ui.instantiateImageCodec(out);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, lessThanOrEqualTo(768));
      expect(frame.image.height, lessThanOrEqualTo(768));
      // Portrait aspect preserved (not forced square).
      expect(frame.image.height, greaterThan(frame.image.width));
      frame.image.dispose();
    });
  });
}

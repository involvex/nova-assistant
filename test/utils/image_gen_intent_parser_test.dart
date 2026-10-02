import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/image_gen_intent_parser.dart';

void main() {
  group('ImageGenIntentParser.tryParse', () {
    test('parses English generate-an-image asks', () {
      expect(
        ImageGenIntentParser.tryParse('generate an image of a red apple'),
        'a red apple',
      );
      expect(
        ImageGenIntentParser.tryParse('Can you create a picture of a cat'),
        'a cat',
      );
      expect(
        ImageGenIntentParser.tryParse('draw me an image of a forest'),
        'a forest',
      );
    });

    test('parses German asks', () {
      expect(
        ImageGenIntentParser.tryParse('erzeuge ein Bild von einem Hund'),
        'einem Hund',
      );
      expect(
        ImageGenIntentParser.tryParse(
          'kannst du ein Bild von einer Stadt '
          'machen',
        ),
        'einer Stadt',
      );
    });

    test('parses bare noun form', () {
      expect(
        ImageGenIntentParser.tryParse('a picture of a lighthouse'),
        'a lighthouse',
      );
    });

    test('returns null for non-image asks', () {
      expect(ImageGenIntentParser.tryParse('what is the weather'), isNull);
      expect(ImageGenIntentParser.tryParse('open settings'), isNull);
      expect(ImageGenIntentParser.tryParse(''), isNull);
      expect(ImageGenIntentParser.tryParse('generate an image of '), isNull);
    });

    test('does not hijack questions about existing images', () {
      expect(
        ImageGenIntentParser.tryParse('describe this image for me'),
        isNull,
      );
      expect(
        ImageGenIntentParser.tryParse(
          'analyze the screenshot and tell me '
          'what is on the screen',
        ),
        isNull,
      );
      expect(
        ImageGenIntentParser.tryParse(
          'schau mal auf das Bild und sag was '
          'drauf ist',
        ),
        isNull,
      );
    });
  });
}

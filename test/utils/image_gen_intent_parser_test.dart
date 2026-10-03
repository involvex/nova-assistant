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

    test('strips punctuation separators left by the colon form', () {
      // "generate an image of: a cat" — the colon is a separator the user
      // typed, not part of the subject. It must not reach the diffusion model.
      expect(
        ImageGenIntentParser.tryParse('generate an image of: a cat'),
        'a cat',
      );
      expect(
        ImageGenIntentParser.tryParse('make a picture - a lighthouse'),
        'a lighthouse',
      );
      expect(
        ImageGenIntentParser.tryParse('draw me an image, a red apple'),
        'a red apple',
      );
    });

    test('tolerates a leading greeting before the ask', () {
      expect(
        ImageGenIntentParser.tryParse('hey, generate an image of a fox'),
        'a fox',
      );
      expect(
        ImageGenIntentParser.tryParse('ok so draw me an image of a cat'),
        'a cat',
      );
      expect(
        ImageGenIntentParser.tryParse('hello! make a picture of a dog'),
        'a dog',
      );
    });

    test('greeting stripping never turns a guarded ask into an image ask', () {
      // Guards run first, so no amount of leading noise can reach `_verbFirst`
      // for a query that is about an existing image.
      for (final prefix in ['', 'hey ', 'ok so ', 'hello! ']) {
        expect(
          ImageGenIntentParser.tryParse('${prefix}describe this image'),
          isNull,
          reason: prefix,
        );
        expect(
          ImageGenIntentParser.tryParse('${prefix}show me the image'),
          isNull,
          reason: prefix,
        );
      }
    });

    test('a greeting never smuggles a non-image ask past the guard', () {
      // `_notImage` runs on the original wording, before greeting stripping,
      // so these must stay in the chat.
      expect(
        ImageGenIntentParser.tryParse('hey, describe this image for me'),
        isNull,
      );
      expect(
        ImageGenIntentParser.tryParse('ok what does this image show'),
        isNull,
      );
    });

    test('still rejects a prompt that is only punctuation', () {
      expect(ImageGenIntentParser.tryParse('generate an image of:'), isNull);
      expect(ImageGenIntentParser.tryParse('make a picture -'), isNull);
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

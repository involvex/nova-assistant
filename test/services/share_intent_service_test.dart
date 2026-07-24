import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/share_intent_service.dart';

void main() {
  group('normalizeSharedText', () {
    test('returns null when subject and text are empty', () {
      expect(normalizeSharedText(), isNull);
      expect(normalizeSharedText(subject: '  ', text: ''), isNull);
    });

    test('returns text alone when subject is empty', () {
      expect(
        normalizeSharedText(text: 'https://example.com'),
        'https://example.com',
      );
    });

    test('returns subject alone when text is empty', () {
      expect(normalizeSharedText(subject: 'Title'), 'Title');
    });

    test('does not duplicate subject already contained in text', () {
      expect(
        normalizeSharedText(
          subject: 'example.com',
          text: 'See https://example.com for more',
        ),
        'See https://example.com for more',
      );
    });

    test('combines subject and text on separate lines', () {
      expect(
        normalizeSharedText(
          subject: 'Interesting article',
          text: 'https://example.com/post',
        ),
        'Interesting article\nhttps://example.com/post',
      );
    });

    test('trims whitespace', () {
      expect(normalizeSharedText(text: '  hello  '), 'hello');
    });
  });
}

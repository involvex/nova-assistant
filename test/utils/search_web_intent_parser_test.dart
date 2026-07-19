import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/search_web_intent_parser.dart';

void main() {
  group('SearchWebIntentParser', () {
    test('parses open google and search for', () {
      expect(
        SearchWebIntentParser.tryParse('open google and search for twitch.tv'),
        'twitch.tv',
      );
    });

    test('parses search the web for', () {
      expect(
        SearchWebIntentParser.tryParse('search the web for missypwns'),
        'missypwns',
      );
    });

    test('parses google query', () {
      expect(
        SearchWebIntentParser.tryParse('google nova assistant'),
        'nova assistant',
      );
    });

    test('returns null for unrelated chat', () {
      expect(SearchWebIntentParser.tryParse('are you okay?'), isNull);
      expect(SearchWebIntentParser.tryParse('open youtube'), isNull);
    });
  });
}

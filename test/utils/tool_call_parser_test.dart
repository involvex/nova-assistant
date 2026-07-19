import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/utils/tool_call_parser.dart';

void main() {
  group('ToolCallParser', () {
    test('parses flat JSON tool call', () {
      final calls = ToolCallParser.parse(
        '{"name":"search_web","arguments":{"query":"Missypwns twitch"}}',
      );

      expect(calls, isNotNull);
      expect(calls!.single['name'], 'search_web');
      expect((calls.single['args'] as Map)['query'], 'Missypwns twitch');
    });

    test('parses ChatML google_search markup and aliases to search_web', () {
      const raw =
          '<|tool_call>call:google_search{queries:[<|"|>Missypwns twitch'
          '<|"|>]}<tool_call|>';
      final calls = ToolCallParser.parse(raw);

      expect(calls, isNotNull);
      expect(calls!.single['name'], 'search_web');
      expect((calls.single['args'] as Map)['query'], 'Missypwns twitch');
    });

    test('stripMarkup removes tool call noise', () {
      const raw =
          'Looking up…\n'
          '<|tool_call>call:google_search{queries:[<|"|>x<|"|>]}'
          '<tool_call|>\n'
          'Done.';
      final cleaned = ToolCallParser.stripMarkup(raw);

      expect(cleaned.contains('tool_call'), isFalse);
      expect(cleaned.contains('google_search'), isFalse);
      expect(cleaned.contains('Looking up'), isTrue);
      expect(cleaned.contains('Done'), isTrue);
    });

    test('returns null for ordinary prose', () {
      expect(ToolCallParser.parse('Hello, how can I help?'), isNull);
    });
  });
}

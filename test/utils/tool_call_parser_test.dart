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

    test('stripMarkup removes ChatML and Gemma turn markers', () {
      const raw =
          '<|im_start|>assistant When learning a language…<|im_end|>\n'
          '<start_of_turn>model Hello<end_of_turn>';
      final cleaned = ToolCallParser.stripMarkup(raw);

      expect(cleaned.contains('im_start'), isFalse);
      expect(cleaned.contains('im_end'), isFalse);
      expect(cleaned.contains('start_of_turn'), isFalse);
      expect(cleaned.contains('end_of_turn'), isFalse);
      expect(cleaned.contains('When learning'), isTrue);
      expect(cleaned.contains('Hello'), isTrue);
    });

    test('returns null for ordinary prose', () {
      expect(ToolCallParser.parse('Hello, how can I help?'), isNull);
    });

    test('ignores bare call: markup without tool_call delimiter', () {
      const prose =
          'I would call:open_app{package:com.android.chrome} if tools worked.';
      expect(ToolCallParser.parse(prose), isNull);
    });

    test('does not alias short words like search or time', () {
      expect(
        ToolCallParser.normalizeCall({
          'name': 'search',
          'args': {'query': 'x'},
        })['name'],
        'search',
      );
      expect(
        ToolCallParser.normalizeCall({
          'name': 'time',
          'args': <String, dynamic>{},
        })['name'],
        'time',
      );
    });
  });
}

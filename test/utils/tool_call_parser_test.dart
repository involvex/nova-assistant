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

    test('parses OpenAI role tool_calls envelope', () {
      const raw =
          '{"role":"assistant","tool_calls":[{"type":"function",'
          '"function":{"name":"get_time","arguments":{}}}]}';
      final calls = ToolCallParser.parse(raw);

      expect(calls, isNotNull);
      expect(calls!.single['name'], 'get_time');
    });

    test('parses concatenated role tool_calls envelopes', () {
      const one =
          '{"role":"assistant","tool_calls":[{"type":"function",'
          '"function":{"name":"get_time","arguments":{}}}]}';
      final calls = ToolCallParser.parse('$one$one');

      expect(calls, isNotNull);
      expect(calls!.length, 2);
      expect(calls.every((c) => c['name'] == 'get_time'), isTrue);
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

    test('stripMarkup removes role tool_calls JSON from bubble', () {
      const raw =
          'Sure.\n'
          '{"role":"assistant","tool_calls":[{"type":"function",'
          '"function":{"name":"get_time","arguments":{}}}]}'
          '{"role":"assistant","tool_calls":[{"type":"function",'
          '"function":{"name":"get_time","arguments":{}}}]}';
      final cleaned = ToolCallParser.stripMarkup(raw);

      expect(cleaned.contains('tool_calls'), isFalse);
      expect(cleaned.contains('get_time'), isFalse);
      expect(cleaned.contains('Sure'), isTrue);
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

    test('maps duration_minutes to wall-clock hour/minute', () {
      final fixed = DateTime(2026, 7, 19, 16, 30);
      final call = ToolCallParser.normalizeCall({
        'name': 'set_alarm',
        'args': {'duration_minutes': 10},
      }, now: fixed);
      final args = call['args'] as Map<String, dynamic>;

      expect(args['hour'], 16);
      expect(args['minute'], 40);
      expect(args['message'], 'Timer 10 min');
      expect(args.containsKey('duration_minutes'), isFalse);
    });

    test('parses ChatML set_alarm with unquoted duration_minutes', () {
      const raw = '<|tool_call>call:set_alarm{duration_minutes:10}<tool_call|>';
      final calls = ToolCallParser.parse(raw);
      expect(calls, isNotNull);
      expect(calls!.single['name'], 'set_alarm');
      final args = calls.single['args'] as Map<String, dynamic>;
      expect(args['hour'], isA<int>());
      expect(args['minute'], isA<int>());
      expect(args.containsKey('duration_minutes'), isFalse);
      expect(args['message'], 'Timer 10 min');
    });

    test('callSignature is stable for same args', () {
      final a = ToolCallParser.callSignature('get_time', {});
      final b = ToolCallParser.callSignature('get_time', {});
      expect(a, b);
      expect(
        ToolCallParser.callSignature('set_alarm', {'hour': 1, 'minute': 2}),
        isNot(
          ToolCallParser.callSignature('set_alarm', {'hour': 1, 'minute': 3}),
        ),
      );
    });
  });
}

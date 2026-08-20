import 'dart:convert';

/// Parses model-emitted tool calls (JSON and ChatML-ish text) into Nova tools.
class ToolCallParser {
  const ToolCallParser._();

  /// Common hallucinated names → Nova built-in tool names.
  ///
  /// Keep aliases specific — short names like `search` / `time` cause false
  /// positives when the model narrates tool use in prose.
  static const aliases = <String, String>{
    'google_search': 'search_web',
    'web_search': 'search_web',
    'bing_search': 'search_web',
    'duckduckgo_search': 'search_web',
    'open_browser': 'search_web',
    'browser_search': 'search_web',
    'get_current_time': 'get_time',
    'current_time': 'get_time',
    'set_an_alarm': 'set_alarm',
    'create_alarm': 'set_alarm',
    'set_timer': 'set_alarm',
    'create_timer': 'set_alarm',
    'launch_app': 'open_app',
    'start_app': 'open_app',
    'open_application': 'open_app',
    'capture_screen': 'take_screenshot',
    'take_a_screenshot': 'take_screenshot',
    'check_weather': 'get_weather',
    'get_current_weather': 'get_weather',
    'force_stop': 'force_stop_app',
    'kill_app': 'force_stop_app',
    'stop_app': 'force_stop_app',
    'draw_image': 'generate_image',
    'create_image': 'generate_image',
    'make_image': 'generate_image',
    'generate_picture': 'generate_image',
    'create_picture': 'generate_image',
    'draw_picture': 'generate_image',
    'make_picture': 'generate_image',
  };

  /// Returns normalized tool calls, or null if none found.
  static List<Map<String, dynamic>>? parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final fromJson = _parseJsonCalls(trimmed);
    if (fromJson != null && fromJson.isNotEmpty) {
      return fromJson.map(normalizeCall).toList();
    }

    final fromMarkup = _parseMarkupCalls(trimmed);
    if (fromMarkup.isNotEmpty) {
      return fromMarkup.map(normalizeCall).toList();
    }

    return null;
  }

  /// Maps aliases and argument shapes to what the native executor expects.
  static Map<String, dynamic> normalizeCall(
    Map<String, dynamic> call, {
    DateTime? now,
  }) {
    final rawName = (call['name'] as String? ?? '').trim();
    final lower = rawName.toLowerCase();
    final name = aliases[rawName] ?? aliases[lower] ?? rawName;
    final args = Map<String, dynamic>.from(
      (call['args'] as Map?) ?? const <String, dynamic>{},
    );

    if (name == 'search_web') {
      final query = _firstString(args, const [
        'query',
        'q',
        'search',
        'text',
        'queries',
      ]);
      if (query != null) {
        args
          ..remove('queries')
          ..remove('q')
          ..remove('search')
          ..remove('text');
        args['query'] = query;
      }
    }

    if (name == 'open_app' || name == 'force_stop_app') {
      final pkg = _firstString(args, const [
        'package',
        'package_name',
        'app',
        'application',
      ]);
      if (pkg != null) {
        args['package'] = pkg;
      }
    }

    if (name == 'set_alarm') {
      _normalizeAlarmArgs(args, now: now);
    }

    return {'name': name, 'args': args};
  }

  /// Canonical signature for same-call dedupe across tool rounds.
  static String callSignature(String name, Map<String, dynamic> args) {
    final keys = args.keys.map((k) => k.toString()).toList()..sort();
    final canonical = <String, dynamic>{};
    for (final key in keys) {
      canonical[key] = args[key];
    }

    return '$name:${jsonEncode(canonical)}';
  }

  /// Removes tool-call markup, role/JSON tool envelopes, and chat-template
  /// tokens from assistant text so they never fill the chat bubble.
  static String stripMarkup(String text) {
    var out = text;
    out = out.replaceAll(
      RegExp(
        r'<\|?tool_call\|?>[\s\S]*?(?:</?\|?tool_call\|?>|<tool_call\|>|$)',
        caseSensitive: false,
      ),
      '',
    );
    // ChatML: <|im_start|>role ... <|im_end|> (role may follow the tag)
    out = out.replaceAll(
      RegExp(
        r'<\|im_start\|>\s*(system|user|assistant)?\s*',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(RegExp(r'<\|im_end\|>', caseSensitive: false), '');
    // Gemma / MediaPipe turn markers
    out = out.replaceAll(
      RegExp(
        r'<start_of_turn>\s*(system|user|model|assistant)?\s*',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(RegExp(r'<end_of_turn>', caseSensitive: false), '');
    // Orphan special-token leftovers
    out = out.replaceAll(RegExp(r'<\|[^|>]{0,32}\|>'), '');
    out = out.replaceAll(RegExp(r'<\|?"?\|>'), '');
    out = _stripToolJsonArtifacts(out);
    out = out.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return out.trim();
  }

  /// Maps relative timer durations to wall-clock hour/minute.
  static void _normalizeAlarmArgs(Map<String, dynamic> args, {DateTime? now}) {
    final hasHour =
        args['hour'] is num ||
        (args['hour'] is String &&
            int.tryParse(args['hour'] as String) != null);
    final hasMinute =
        args['minute'] is num ||
        (args['minute'] is String &&
            int.tryParse(args['minute'] as String) != null);

    final duration = _asPositiveInt(
      args['duration_minutes'] ??
          args['duration'] ??
          args['minutes'] ??
          args['durationMinutes'],
    );

    if (duration != null && duration > 0 && (!hasHour || !hasMinute)) {
      final clock = (now ?? DateTime.now()).add(Duration(minutes: duration));
      args['hour'] = clock.hour;
      args['minute'] = clock.minute;
      final existing = args['message'];
      if (existing is! String || existing.trim().isEmpty) {
        args['message'] = 'Timer $duration min';
      }
    }

    if (args['hour'] is String) {
      final h = int.tryParse(args['hour'] as String);
      if (h != null) args['hour'] = h;
    }
    if (args['minute'] is String) {
      final m = int.tryParse(args['minute'] as String);
      if (m != null) args['minute'] = m;
    }

    args
      ..remove('duration_minutes')
      ..remove('duration')
      ..remove('minutes')
      ..remove('durationMinutes');
  }

  static int? _asPositiveInt(dynamic raw) {
    if (raw is int) return raw > 0 ? raw : null;
    if (raw is num) {
      final v = raw.toInt();

      return v > 0 ? v : null;
    }
    if (raw is String) {
      final v = int.tryParse(raw.trim());
      if (v != null && v > 0) return v;
    }

    return null;
  }

  /// Removes OpenAI-style role/tool_calls JSON and bare name/arguments tool
  /// objects (including concatenated repeats) from visible text.
  static String _stripToolJsonArtifacts(String text) {
    if (!text.contains('{')) return text;

    final buffer = StringBuffer();
    var i = 0;
    while (i < text.length) {
      if (text[i] != '{') {
        buffer.write(text[i]);
        i++;
        continue;
      }

      final end = _matchingBraceEnd(text, i);
      if (end < 0) {
        buffer.write(text.substring(i));
        break;
      }

      final candidate = text.substring(i, end + 1);
      if (_looksLikeToolJson(candidate)) {
        i = end + 1;
        continue;
      }

      buffer.write(candidate);
      i = end + 1;
    }

    return buffer.toString();
  }

  static int _matchingBraceEnd(String text, int start) {
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == '\\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }

    return -1;
  }

  static bool _looksLikeToolJson(String candidate) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is! Map) return false;
      final map = Map<String, dynamic>.from(decoded);
      if (map['tool_calls'] is List) return true;
      final name = map['name'];
      if (name is String && name.trim().isNotEmpty) {
        if (map.containsKey('arguments') ||
            map.containsKey('args') ||
            map['type'] == 'function') {
          return true;
        }
      }
      final role = map['role'];
      if (role is String &&
          (role == 'assistant' || role == 'tool') &&
          map.containsKey('tool_calls')) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  static List<Map<String, dynamic>>? _parseJsonCalls(String text) {
    final results = <Map<String, dynamic>>[];

    // Concatenated role envelopes: {...}{...}
    var searchFrom = 0;
    while (searchFrom < text.length) {
      final start = text.indexOf('{', searchFrom);
      if (start < 0) break;
      final end = _matchingBraceEnd(text, start);
      if (end < 0) break;
      final candidate = text.substring(start, end + 1);
      final decoded = _tryDecodeMap(candidate);
      searchFrom = end + 1;
      if (decoded == null) continue;

      if (decoded['tool_calls'] is List) {
        for (final call in decoded['tool_calls'] as List) {
          if (call is! Map) continue;
          final fn = call['function'] as Map?;
          final name = (fn?['name'] ?? call['name']) as String?;
          if (name == null || name.isEmpty) continue;
          results.add({
            'name': name,
            'args': _coerceArguments(fn?['arguments'] ?? call['arguments']),
          });
        }
        continue;
      }

      if (decoded['name'] is String) {
        results.add({
          'name': decoded['name'] as String,
          'args': _coerceArguments(decoded['arguments'] ?? decoded['args']),
        });
      }
    }

    if (results.isEmpty) return null;

    return results;
  }

  static Map<String, dynamic>? _tryDecodeMap(String candidate) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}

    return null;
  }

  /// Handles forms like:
  /// `<|tool_call>call:google_search{queries:[<|"|>Missypwns twitch<|"|>]}`
  ///
  /// Requires a tool-call delimiter so explanatory prose such as
  /// `call:open_app{package:...}` is not executed as a real tool.
  static List<Map<String, dynamic>> _parseMarkupCalls(String text) {
    final results = <Map<String, dynamic>>[];
    final pattern = RegExp(
      r'<\|?tool_call\|?>\s*call:\s*([a-zA-Z0-9_]+)\s*(\{[\s\S]*?\})\s*'
      r'(?:</?\|?tool_call\|?>|<tool_call\|>)?',
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(text)) {
      final name = match.group(1);
      final rawArgs = match.group(2);
      if (name == null || rawArgs == null) continue;
      results.add({'name': name, 'args': _parseLooseArgs(rawArgs)});
    }

    return results;
  }

  static Map<String, dynamic> _parseLooseArgs(String raw) {
    // Normalize ChatML quote tokens only — do not rewrite apostrophes in
    // queries like "today's weather".
    final asJson = raw.replaceAll(RegExp(r'<\|?"?\|>'), '"');
    try {
      final decoded = jsonDecode(asJson);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Fall through to heuristic parsing.
    }

    // Quote bare keys so {duration_minutes:10} can decode.
    try {
      final quotedKeys = asJson.replaceAllMapped(
        RegExp(r'([{\[,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'),
        (m) => '${m[1]}"${m[2]}":',
      );
      final decoded = jsonDecode(quotedKeys);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Fall through.
    }

    final args = <String, dynamic>{};
    final queriesMatch = RegExp(
      r'queries\s*:\s*\[\s*(.*?)\s*\]',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    if (queriesMatch != null) {
      final items = _splitLooseList(queriesMatch.group(1) ?? '');
      if (items.length == 1) {
        args['query'] = items.first;
      } else if (items.isNotEmpty) {
        args['queries'] = items;
      }
    }

    final queryMatch = RegExp(
      r'''query\s*:\s*["']?(.*?)["']?\s*(?:,|\})''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    if (queryMatch != null && !args.containsKey('query')) {
      args['query'] = _cleanLooseString(queryMatch.group(1) ?? '');
    }

    final packageMatch = RegExp(
      r'''package\s*:\s*["']?([a-zA-Z0-9._]+)["']?''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (packageMatch != null) {
      args['package'] = packageMatch.group(1);
    }

    final durationMatch = RegExp(
      r'''(?:duration_minutes|durationMinutes|duration|minutes)\s*:\s*(\d+)''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (durationMatch != null) {
      args['duration_minutes'] = int.parse(durationMatch.group(1)!);
    }

    final hourMatch = RegExp(
      r'''hour\s*:\s*(\d+)''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (hourMatch != null) {
      args['hour'] = int.parse(hourMatch.group(1)!);
    }

    final minuteMatch = RegExp(
      r'''minute\s*:\s*(\d+)''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (minuteMatch != null) {
      args['minute'] = int.parse(minuteMatch.group(1)!);
    }

    return args;
  }

  static List<String> _splitLooseList(String body) {
    final parts = body.split(',');

    return parts.map(_cleanLooseString).where((s) => s.isNotEmpty).toList();
  }

  static String _cleanLooseString(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'<\|?"?\|>'), '');
    s = s.replaceAll(RegExp(r'''^["']+|["']+$'''), '');

    return s.trim();
  }

  static String? _firstString(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final value = args[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is List && value.isNotEmpty) {
        final joined = value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .join(' ');
        if (joined.isNotEmpty) return joined;
      }
    }

    return null;
  }

  static Map<String, dynamic> _coerceArguments(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    return <String, dynamic>{};
  }
}

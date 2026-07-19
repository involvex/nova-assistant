import 'dart:convert';

/// Parses model-emitted tool calls (JSON and ChatML-ish text) into Nova tools.
class ToolCallParser {
  const ToolCallParser._();

  /// Common hallucinated names → Nova built-in tool names.
  static const aliases = <String, String>{
    'google_search': 'search_web',
    'web_search': 'search_web',
    'search': 'search_web',
    'bing_search': 'search_web',
    'duckduckgo': 'search_web',
    'open_browser': 'search_web',
    'browser_search': 'search_web',
    'get_current_time': 'get_time',
    'current_time': 'get_time',
    'time': 'get_time',
    'set_an_alarm': 'set_alarm',
    'create_alarm': 'set_alarm',
    'launch_app': 'open_app',
    'start_app': 'open_app',
    'open_application': 'open_app',
    'screenshot': 'take_screenshot',
    'capture_screen': 'take_screenshot',
    'weather': 'get_weather',
    'check_weather': 'get_weather',
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
  static Map<String, dynamic> normalizeCall(Map<String, dynamic> call) {
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

    if (name == 'open_app') {
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

    return {'name': name, 'args': args};
  }

  /// Removes tool-call markup so it is not shown in the chat UI.
  ///
  /// Also strips incomplete/in-progress tool markup so streaming tokens do not
  /// flicker raw `<|tool_call>...` into the bubble.
  static String stripMarkup(String text) {
    var out = text;
    out = out.replaceAll(
      RegExp(
        r'<\|?tool_call\|?>[\s\S]*?(?:</?\|?tool_call\|?>|<tool_call\|>|$)',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(
      RegExp(
        r'call:\s*[a-zA-Z0-9_]+\s*\{[^{}]*(?:\}|$)',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(RegExp(r'<\|?"?\|>'), '');
    out = out.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return out.trim();
  }

  static List<Map<String, dynamic>>? _parseJsonCalls(String text) {
    final decoded = _decodeJsonObject(text);
    if (decoded == null) return null;

    final results = <Map<String, dynamic>>[];

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
      if (results.isNotEmpty) return results;
    }

    if (decoded['name'] is String) {
      results.add({
        'name': decoded['name'] as String,
        'args': _coerceArguments(decoded['arguments'] ?? decoded['args']),
      });

      return results;
    }

    return null;
  }

  /// Handles forms like:
  /// `<|tool_call>call:google_search{queries:[<|"|>Missypwns twitch<|"|>]}`
  static List<Map<String, dynamic>> _parseMarkupCalls(String text) {
    final results = <Map<String, dynamic>>[];
    final pattern = RegExp(
      r'(?:<\|?tool_call\|?>)?\s*call:\s*([a-zA-Z0-9_]+)\s*(\{[\s\S]*?\})\s*'
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

  static Map<String, dynamic>? _decodeJsonObject(String text) {
    try {
      final trimmed = text.trim();
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final candidate = trimmed.substring(start, end + 1);
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}

    return null;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Shared JSON chip parsing for LLM-generated starters / follow-ups / presets.
class SuggestionJsonParser {
  SuggestionJsonParser._();

  /// Parse a JSON array of strings from model output (tolerates prose wrappers).
  static List<String> parseStringList(String raw, {int max = 3}) {
    final decoded = _decodeList(raw);
    if (decoded == null) return const [];

    return decoded
        .map(_asTrimmedString)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .take(max)
        .toList();
  }

  /// Parse starter chips: `{"label","prompt"}` objects or plain strings.
  static List<({String label, String prompt})> parseLabeledPrompts(
    String raw, {
    int max = 4,
  }) {
    final decoded = _decodeList(raw);
    if (decoded == null) return const [];

    final out = <({String label, String prompt})>[];
    for (final item in decoded) {
      if (out.length >= max) break;
      if (item is Map) {
        final label = _asTrimmedString(item['label'] ?? item['name']);
        final prompt = _asTrimmedString(item['prompt'] ?? item['text']);
        if (label != null &&
            prompt != null &&
            label.isNotEmpty &&
            prompt.isNotEmpty) {
          out.add((label: label, prompt: prompt));
        }
      } else {
        final text = _asTrimmedString(item);
        if (text != null && text.isNotEmpty) {
          final label = text.length <= 28 ? text : '${text.substring(0, 25)}…';
          out.add((label: label, prompt: text));
        }
      }
    }

    return out;
  }

  /// Parse preset drafts: name / prompt / optional description & category.
  static List<
    ({String name, String prompt, String? description, String? category})
  >
  parsePresetDrafts(String raw, {int max = 5}) {
    final decoded = _decodeList(raw);
    if (decoded == null) return const [];

    final out =
        <
          ({String name, String prompt, String? description, String? category})
        >[];
    for (final item in decoded) {
      if (out.length >= max) break;
      if (item is! Map) continue;
      final name = _asTrimmedString(item['name'] ?? item['label']);
      final prompt = _asTrimmedString(item['prompt']);
      if (name == null || prompt == null || name.isEmpty || prompt.isEmpty) {
        continue;
      }
      out.add((
        name: name,
        prompt: prompt,
        description: _asTrimmedString(item['description']),
        category: _asTrimmedString(item['category']),
      ));
    }

    return out;
  }

  static List<dynamic>? _decodeList(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    try {
      final start = trimmed.indexOf('[');
      final end = trimmed.lastIndexOf(']');
      if (start == -1 || end <= start) return null;
      final decoded = jsonDecode(trimmed.substring(start, end + 1));
      if (decoded is List) return decoded;
    } catch (e) {
      debugPrint('SuggestionJsonParser: $e');
    }

    return null;
  }

  static String? _asTrimmedString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }
}

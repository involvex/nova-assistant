/// Parses natural-language web-search requests into a search query string.
class SearchWebIntentParser {
  SearchWebIntentParser._();

  static final RegExp _patterns = RegExp(
    r'^\s*(?:'
    r'(?:please\s+)?'
    r'(?:can\s+you\s+)?'
    r'(?:open\s+(?:google|the\s+browser|browser)\s+and\s+)?'
    r'(?:(?:search|google|look\s*up|finde?)\s+(?:(?:the\s+)?web\s+|online\s+|for\s+)?)'
    r'|'
    r'(?:suche\s+(?:im\s+netz\s+|online\s+|nach\s+)?)'
    r')'
    r'(.+?)\s*$',
    caseSensitive: false,
  );

  /// Returns the search string when [query] is clearly a web-search ask.
  static String? tryParse(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    final match = _patterns.firstMatch(trimmed);
    if (match == null) return null;

    var term = (match.group(1) ?? '').trim();
    // Strip leading "for " / "nach " leftovers.
    term = term.replaceFirst(
      RegExp(r'^(for|nach)\s+', caseSensitive: false),
      '',
    );
    if (term.length < 2) return null;

    return term;
  }
}

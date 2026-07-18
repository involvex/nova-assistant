/// Resolves natural-language "open app" requests to Android package names.
class OpenAppIntentParser {
  OpenAppIntentParser._();

  /// ASCII open verbs (safe with `\b`). Umlaut forms use normalized matching.
  static final RegExp _asciiOpenIntent = RegExp(
    r'\b(open|launch|start|starte|oeffne|oeffnen|aufmachen)\b',
    caseSensitive: false,
  );

  static final RegExp _machAufIntent = RegExp(
    r'\bmach(?:en)?\s+\S+\s+auf\b',
    caseSensitive: false,
  );

  /// Common app aliases → package names.
  static const Map<String, String> knownApps = {
    'youtube': 'com.google.android.youtube',
    'yt': 'com.google.android.youtube',
    'settings': 'com.android.settings',
    'einstellungen': 'com.android.settings',
    'chrome': 'com.android.chrome',
    'maps': 'com.google.android.apps.maps',
    'google maps': 'com.google.android.apps.maps',
    'kamera': 'com.android.camera',
    'camera': 'com.android.camera',
    'photos': 'com.google.android.apps.photos',
    'galeria': 'com.google.android.apps.photos',
    'gallery': 'com.google.android.apps.photos',
    'whatsapp': 'com.whatsapp',
    'spotify': 'com.spotify.music',
    'clock': 'com.android.deskclock',
    'uhr': 'com.android.deskclock',
    'wecker': 'com.android.deskclock',
  };

  /// Normalize German umlauts so ASCII `\b` works ("öffne" → "oeffne").
  /// Also prevents "geöffnet" → "geoeffnet" from matching `\boeffne\b`.
  static String _normalize(String query) {
    return query
        .toLowerCase()
        .replaceAll('ö', 'oe')
        .replaceAll('ä', 'ae')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
  }

  static bool _hasOpenIntent(String query) {
    final normalized = _normalize(query);
    if (_asciiOpenIntent.hasMatch(normalized)) return true;
    if (_machAufIntent.hasMatch(normalized)) return true;

    return false;
  }

  /// Returns a package name when [query] clearly asks to open a known app.
  static String? tryParsePackage(String query) {
    if (!_hasOpenIntent(query)) return null;

    final lower = query.toLowerCase();
    // Prefer longer aliases first (e.g. "google maps" before "maps").
    final aliases = knownApps.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final alias in aliases) {
      if (lower.contains(alias)) {
        return knownApps[alias];
      }
    }

    return null;
  }
}

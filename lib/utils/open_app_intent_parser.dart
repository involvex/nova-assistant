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

  /// Explicit Android package id (at least 3 dotted segments).
  static final RegExp packageIdPattern = RegExp(
    r'\b([a-zA-Z][\w]*(\.[a-zA-Z][\w]*){2,})\b',
  );

  /// Common app aliases → package names.
  ///
  /// `browser` / `chrome` use Chrome when installed; open_app falls back via
  /// package visibility + launcher query for other apps.
  static const Map<String, String> knownApps = {
    'yt revanced': 'app.revanced.android.youtube',
    'youtube revanced': 'app.revanced.android.youtube',
    'revanced youtube': 'app.revanced.android.youtube',
    'revanced': 'app.revanced.android.youtube',
    'morphe youtube': 'app.morphe.android.youtube',
    'morphe': 'app.morphe.android.youtube',
    'youtube': 'com.google.android.youtube',
    'yt': 'com.google.android.youtube',
    'settings': 'com.android.settings',
    'einstellungen': 'com.android.settings',
    'chrome canary': 'com.chrome.canary',
    'chrome beta': 'com.chrome.beta',
    'chrome dev': 'com.chrome.dev',
    'chrome': 'com.android.chrome',
    'browser': 'com.android.chrome',
    'google chrome': 'com.android.chrome',
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

  /// Returns a package id embedded in [query], if any.
  static String? extractPackageId(String query) {
    final match = packageIdPattern.firstMatch(query);

    return match?.group(1);
  }

  /// Returns a package name when [query] clearly asks to open an app.
  ///
  /// Explicit package ids always win over aliases (so
  /// `open app.revanced.android.youtube` is not rewritten to stock YouTube
  /// just because the string contains "youtube").
  static String? tryParsePackage(String query) {
    if (!_hasOpenIntent(query)) return null;

    final explicit = extractPackageId(query);
    if (explicit != null) return explicit;

    final lower = _normalize(query);
    // Prefer longer aliases first (e.g. "yt revanced" before "yt").
    final aliases = knownApps.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final alias in aliases) {
      final pattern = RegExp(
        '\\b${RegExp.escape(alias)}\\b',
        caseSensitive: false,
      );
      if (pattern.hasMatch(lower)) {
        return knownApps[alias];
      }
    }

    return null;
  }
}

/// Parses natural-language "generate an image" requests into a diffusion prompt.
///
/// Mirrors [SearchWebIntentParser]: a deterministic host-side shortcut so short
/// chats like "generate an image of a red apple" do not have to round-trip
/// through the LLM tool-calling loop.
class ImageGenIntentParser {
  ImageGenIntentParser._();

  // NOTE: raw strings in Dart do not interpolate, so the shared fragments are
  // spliced in with `+` instead of `$fragment` inside r'...'.
  static const String _polite =
      '(?:please\\s+|can\\s+you\\s+|'
      'could\\s+you\\s+|kannst\\s+du\\s+|kann\\s+bitte\\s+)?';

  static const String _article =
      '(?:me\\s+|us\\s+|mir\\s+|ein[e]?\\s+|eine\\s+|dem\\s+)?';

  static const String _anArticle = '(?:an?\\s+|the\\s+|some\\s+|new\\s+)?';

  static const String _imageNoun =
      '(?:image|picture|photo|artwork|'
      'illustration|painting|drawing|bild(?:er)?|foto(?:s)?|'
      'gemälde|kunstwerk|zeichnung)';

  static const String _connector =
      '(?:von|of|about|with|showing|mit|über)?\\s*';

  static const String _generateVerb =
      '(?:generate|create|make|draw|paint|render|produce)';

  static const String _germanVerb =
      '(?:erzeuge|erstelle|mache|mal(?:e|te)|zeichne|rendere)';

  /// Verb-first asks: "generate an image of a red apple", "erzeuge ein Bild
  /// von einem Hund".
  static final RegExp _verbFirst = RegExp(
    '^\\s*'
    '$_polite'
    '(?:'
    '$_generateVerb\\s+$_article$_anArticle$_imageNoun\\s*$_connector'
    '|'
    '$_germanVerb\\s+$_article$_imageNoun\\s*$_connector'
    ')'
    '(.+?)\\s*\$',
    caseSensitive: false,
  );

  /// Verb-last asks: "kannst du ein Bild von einer Stadt machen".
  static final RegExp _verbLast = RegExp(
    '^\\s*'
    '$_polite'
    '$_article'
    '$_anArticle'
    '$_imageNoun\\s*'
    '$_connector'
    '(.+?)'
    '\\s+(?:machen|malen|zeichnen|erstellen|erzeugen|rendern|'
    'make|create|generate|draw|paint|render)\\s*[.!?]*\$',
    caseSensitive: false,
  );

  /// A greeting or interjection before the real ask: "hey, generate an image
  /// of a fox", "ok so draw me a cat". Dropped so the verb-first anchor below
  /// still matches. Without this the parser falls through to the LLM, which
  /// has no reliable way to emit the tool call and just echoes the message.
  ///
  /// Trailing whitespace is required so a word glued to the subject is never
  /// eaten. This is safe because stripping happens before the match and the
  /// remainder must still satisfy an image-ask regex: "a picture of sofas" does
  /// not start with "so" and is untouched, while "so draw me a cat" becomes
  /// "draw me a cat".
  static final RegExp _leadingInterjection = RegExp(
    r'^(?:hey|hello|hi|yo|ok|okay|so|um|well|please|pls)\s*[!,.]?\s+',
    caseSensitive: false,
  );

  /// Bare noun form: "a picture of a lighthouse", "ein Bild von einem Turm".
  static final RegExp _bareNoun = RegExp(
    '^\\s*(?:ein[e]?\\s+|a\\s+|an\\s+)?'
    '(?:bild|foto|gemälde|zeichnung|image|picture|photo|artwork)\\s+'
    '(?:von|of|mit|with)\\s+(.+?)\\s*\$',
    caseSensitive: false,
  );

  /// Phrases that *look* like image asks but must stay in the chat, because
  /// they are about existing images rather than generating new ones.
  static final RegExp _notImage = RegExp(
    r'\b(?:'
    r'describ\w*|erklär\w*|analysier\w*|analyz\w*|'
    r'was\s+zeigt|what\s+(?:does|is)\s+(?:in|on)|'
    r'read\s+the\s+text|ocr|'
    r'schau\s+(?:mal\s+)?auf|zeig\s+mir\s+das\s+bild|'
    r'show\s+me\s+the\s+(?:image|picture|photo)|'
    r'look\s+at\s+(?:this|my|the)\s+(?:image|picture|photo|screenshot)|'
    r'analy[sz]e\s+(?:this|the)\s+(?:image|picture|photo|screenshot)|'
    r'compress|komprimier|thumbnail|'
    r'remove\s+background|entferne\s+hintergrund'
    r')\b',
    caseSensitive: false,
  );

  /// Strips leading connectors ("von of …") left behind by regex backtracking.
  static final RegExp _leadingConnectors = RegExp(
    r'^(?:von|of|about|mit|with|über|showing)\s+',
    caseSensitive: false,
  );

  /// Separators users type between the ask and the subject: "image of: a cat",
  /// "picture - a lighthouse", "image, a red apple". They are not part of the
  /// subject — a leading ":" reaches the diffusion model as the first token of
  /// the prompt and visibly degrades the result.
  static final RegExp _leadingSeparator = RegExp(r'^[\s:;,\-–—.]+');

  /// A usable subject: at least two real word characters.
  static final RegExp _hasSubject = RegExp(r'[A-Za-z0-9äöüßÄÖÜ]{2,}');

  /// A prompt made of nothing but a connector ("of", "von mit …") has no
  /// subject — the ask was cut short, so the LLM should ask for clarification.
  static final RegExp _connectorOnly = RegExp(
    r'^(?:von|of|about|mit|with|über|showing|and|und|the|der|die|das|a|an)[\s,.]*$',
    caseSensitive: false,
  );

  /// Returns the diffusion prompt when [query] clearly asks for a new image.
  static String? tryParse(String query) {
    final original = query.trim();
    if (original.isEmpty) return null;
    // `_notImage` sees the ORIGINAL wording so "hey, describe this image"
    // stays in the chat; the regexes then run on the greeting-stripped text.
    if (_notImage.hasMatch(original)) return null;

    var trimmed = original;
    while (true) {
      final next = trimmed.replaceFirst(_leadingInterjection, '');
      if (next == trimmed) break;
      trimmed = next;
    }

    if (trimmed.isEmpty) return null;

    final match =
        _verbFirst.firstMatch(trimmed) ??
        _verbLast.firstMatch(trimmed) ??
        _bareNoun.firstMatch(trimmed);
    if (match == null) return null;

    var prompt = (match.group(1) ?? '').trim();
    // Separators first: "of: a cat" only exposes the connector afterwards.
    prompt = prompt.replaceFirst(_leadingSeparator, '').trim();
    prompt = prompt.replaceAll(_leadingConnectors, '').trim();

    // "generate an image of" leaves only a connector behind — let the LLM ask
    // for clarification rather than rendering a prompt-less image.
    if (prompt.isEmpty || _connectorOnly.hasMatch(prompt)) return null;
    if (!_hasSubject.hasMatch(prompt)) return null;

    return prompt;
  }
}

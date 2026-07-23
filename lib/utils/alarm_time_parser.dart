/// Parses natural-language alarm and timer times from user queries.
///
/// Alarm examples: "set an alarm for 7 AM", "Wecker auf 7 Uhr".
/// Timer examples: "timer for 10 minutes", "stell mir einen Timer für 10 Minuten".
class AlarmTimeParser {
  AlarmTimeParser._();

  static final RegExp _alarmIntent = RegExp(
    r'\b('
    r'set\s+(an?\s+)?alarm|alarm\s+(for|at)|wake\s+me|'
    r'wecker|alarm\s+stellen|'
    r'stell(e|en)?\s+(einen?\s+)?(wecker|alarm)|'
    r'weck\s+mich|'
    r'(wecker|alarm)\s+(auf|um|für|fuer)'
    r')\b',
    caseSensitive: false,
  );

  static final RegExp _timerIntent = RegExp(
    r'\b('
    r'timer|countdown|egg[\s-]?timer|'
    r'set\s+(a\s+)?timer|'
    r'stell(e|en)?\s+(mir\s+)?(einen?\s+)?timer|'
    r'timer\s+(für|fuer|for|auf)|'
    r'in\s+\d+\s*(minutes?|mins?|minuten?)'
    r')\b',
    caseSensitive: false,
  );

  static final RegExp _durationMinutes = RegExp(
    r'\b(?:für|fuer|for|in|auf)?\s*(\d+)\s*(minutes?|mins?|minuten?|min\.?)\b',
    caseSensitive: false,
  );

  static final RegExp _time12h = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b',
    caseSensitive: false,
  );

  static final RegExp _time24h = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');

  static final RegExp _timeGermanUhr = RegExp(
    r'\b(?:um\s+|auf\s+|für\s+|fuer\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*uhr\b',
    caseSensitive: false,
  );

  /// Returns `(hour, minute)` in 24-hour format, or null if not an alarm request
  /// with a parseable time.
  static ({int hour, int minute})? tryParse(String query) {
    if (!_alarmIntent.hasMatch(query)) return null;

    final match12 = _time12h.firstMatch(query);
    if (match12 != null) {
      var hour = int.parse(match12.group(1)!);
      final minute = int.parse(match12.group(2) ?? '0');
      final period = match12.group(3)!.toLowerCase().replaceAll('.', '');

      if (hour < 1 || hour > 12 || minute > 59) return null;

      if (period.startsWith('p') && hour != 12) {
        hour += 12;
      } else if (period.startsWith('a') && hour == 12) {
        hour = 0;
      }

      return (hour: hour, minute: minute);
    }

    final match24 = _time24h.firstMatch(query);
    if (match24 != null) {
      final hour = int.parse(match24.group(1)!);
      final minute = int.parse(match24.group(2)!);
      if (hour > 23 || minute > 59) return null;

      return (hour: hour, minute: minute);
    }

    final matchUhr = _timeGermanUhr.firstMatch(query);
    if (matchUhr != null) {
      final hour = int.parse(matchUhr.group(1)!);
      final minute = int.parse(matchUhr.group(2) ?? '0');
      if (hour > 23 || minute > 59) return null;

      return (hour: hour, minute: minute);
    }

    return null;
  }

  /// Parses relative timers ("10 minutes") into a wall-clock alarm time.
  ///
  /// Uses [now] when provided (tests); otherwise [DateTime.now].
  static ({int hour, int minute, int durationMinutes})? tryParseTimer(
    String query, {
    DateTime? now,
  }) {
    if (!_timerIntent.hasMatch(query)) return null;

    final match = _durationMinutes.firstMatch(query);
    if (match == null) return null;

    final duration = int.parse(match.group(1)!);
    if (duration < 1 || duration > 24 * 60) return null;

    final clock = (now ?? DateTime.now()).add(Duration(minutes: duration));

    return (hour: clock.hour, minute: clock.minute, durationMinutes: duration);
  }
}

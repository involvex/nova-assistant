/// Parses natural-language alarm times from user queries.
///
/// Examples: "set an alarm for 7 AM", "alarm at 7pm", "wake me at 19:30".
class AlarmTimeParser {
  AlarmTimeParser._();

  static final RegExp _alarmIntent = RegExp(
    r'\b(set\s+(an?\s+)?alarm|alarm\s+(for|at)|wake\s+me)\b',
    caseSensitive: false,
  );

  static final RegExp _time12h = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b',
    caseSensitive: false,
  );

  static final RegExp _time24h = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');

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

    // Bare hour with AM/PM already handled; try "at 7" / "for 7" without period
    // only when clearly morning/evening context is absent — skip ambiguous cases.
    return null;
  }
}

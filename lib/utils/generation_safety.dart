import 'package:nova_assistant/models/model_info.dart';

/// Limits and detectors for runaway / looped model output.
class GenerationSafety {
  const GenerationSafety._();

  static const smollmMaxOutputChars = 2000;
  static const gemma3MaxOutputChars = 4000;
  static const largeMaxOutputChars = 6000;

  static const repetitionWindowChars = 80;
  static const repetitionMinRepeats = 3;

  /// Hard cap on streamed assistant text for one turn.
  static int maxOutputCharsFor(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return smollmMaxOutputChars;
      case NovaModel.fastvlm:
      case NovaModel.gemma3_1b:
        return gemma3MaxOutputChars;
      case NovaModel.gemma4E2b:
        return largeMaxOutputChars;
    }
  }

  static int maxOutputCharsForCustom() => largeMaxOutputChars;

  /// True when [text] ends with the same ~80-char block repeated ≥3 times.
  static bool hasConsecutiveRepetition(
    String text, {
    int window = repetitionWindowChars,
    int minRepeats = repetitionMinRepeats,
  }) {
    if (window < 16 || minRepeats < 2) return false;
    final need = window * minRepeats;
    if (text.length < need) return false;

    final chunk = text.substring(text.length - window);
    if (chunk.trim().isEmpty) return false;

    var repeats = 1;
    var end = text.length - window;
    while (repeats < minRepeats && end >= window) {
      final prev = text.substring(end - window, end);
      if (prev != chunk) break;
      repeats++;
      end -= window;
    }

    return repeats >= minRepeats;
  }

  /// Returns a user-facing suffix when [text] hits a safety stop, else null.
  static String? safetyStopMessage(String text, int maxChars) {
    if (text.length >= maxChars) {
      return '\n\n⚠️ Response truncated (length limit).';
    }
    if (hasConsecutiveRepetition(text)) {
      return '\n\n⚠️ Response stopped (repetition detected).';
    }

    return null;
  }
}

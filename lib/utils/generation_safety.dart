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

  /// True when [text] ends with the same block repeated ≥[minRepeats] times.
  ///
  /// Checks every period `p` from 1..[window] so short loops (e.g. "orange"
  /// ×3) are caught, not only exact [window]-char tiles.
  static bool hasConsecutiveRepetition(
    String text, {
    int window = repetitionWindowChars,
    int minRepeats = repetitionMinRepeats,
  }) {
    if (window < 16 || minRepeats < 2) return false;
    if (text.length < 15) return false;

    for (var p = 1; p <= window; p++) {
      if (text.length < p * minRepeats) continue;
      final chunk = text.substring(text.length - p);
      if (chunk.trim().isEmpty) continue;

      var isRepeat = true;
      for (var i = 1; i < minRepeats; i++) {
        final prev = text.substring(
          text.length - p * (i + 1),
          text.length - p * i,
        );
        if (prev != chunk) {
          isRepeat = false;
          break;
        }
      }
      if (isRepeat && p * minRepeats >= 15) {
        return true;
      }
    }

    return false;
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

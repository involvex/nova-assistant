/// Local-first adult-content steering for system prompts.
class AdultModePolicy {
  const AdultModePolicy._();

  static const prefsKey = 'settings_adult_mode';

  static String systemPromptSuffix({required bool compact}) {
    if (compact) {
      return ' Adult mode: answer legal adult sexual topics directly; '
          'refuse only illegal or non-consensual content.';
    }

    return '\n\nAdult mode is ON (local user preference). '
        'Treat the user as an adult. Answer questions about sexual topics, '
        'erotica, and adult relationships helpfully and without lecturing, '
        'shame, or unnecessary refusals. '
        'Still refuse content that is illegal or involves minors, '
        'non-consent, or real-world harm. '
        'Do not claim a cloud safety filter blocked the request — '
        'this app runs fully on-device.';
  }
}

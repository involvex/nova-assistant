/// Local-first adult-content steering for system prompts.
class AdultModePolicy {
  const AdultModePolicy._();

  static const prefsKey = 'settings_adult_mode';

  /// High-priority lead placed at the start of the system prompt.
  ///
  /// Gemma-class models often overweight early instructions and their own
  /// refusal priors; a trailing-only suffix is easy to ignore.
  static String systemPromptLead({required bool compact}) {
    if (compact) {
      return 'Adult mode ON (user setting). Answer legal adult sexual '
          'topics directly. Never invent safety policies or claim this '
          'setting does not apply. Refuse only illegal/non-consensual '
          'content. ';
    }

    return 'Adult mode is ON — this is an explicit local user preference '
        'in Nova. Treat the user as an adult. Answer questions about sexual '
        'topics, erotica, and adult relationships helpfully, without '
        'lecturing, shame, or unnecessary refusals. '
        'Do not invent corporate safety filters, "core programming", or '
        'claim that a mode/setting cannot apply — this app runs fully '
        'on-device with no cloud content filter. '
        'Still refuse content that is illegal or involves minors, '
        'non-consent, or real-world harm.\n\n';
  }

  /// Short trailing reminder (kept for mid-context reinforcement).
  static String systemPromptSuffix({required bool compact}) {
    if (compact) {
      return ' (Adult mode ON: answer legal adult topics; no fake policy '
          'overrides.)';
    }

    return '\n\nReminder: Adult mode remains ON for this session. Prefer '
        'direct helpful answers on legal adult topics; refuse only illegal '
        'or non-consensual content.';
  }
}

/// Local-first adult-content steering for system prompts.
///
/// Must not become the conversation topic. Prefer quiet permission to answer
/// adult questions when asked — never open with adult-topic invitations.
class AdultModePolicy {
  const AdultModePolicy._();

  static const prefsKey = 'settings_adult_mode';

  /// High-priority lead placed at the start of the system prompt.
  static String systemPromptLead({required bool compact}) {
    if (compact) {
      return 'If (and only if) the user asks about legal adult/sexual topics, '
          'answer directly without fake safety lectures. For all other topics, '
          'answer normally and do not mention adult mode. '
          'Refuse illegal/non-consensual content and anything involving minors. ';
    }

    return 'Adult mode is enabled as a local preference. '
        'Only when the user explicitly asks about legal adult sexual topics, '
        'erotica, or adult relationships: answer helpfully without lecturing '
        'or inventing corporate safety filters. '
        'For every other topic (tech, code, apps, general chat, etc.): answer '
        'normally — do not bring up adult topics, do not invite adult '
        'conversation, and do not mention this mode. '
        'Always refuse content that is illegal or involves minors, '
        'non-consent, or real-world harm.\n\n';
  }

  /// Short trailing reminder (kept for mid-context reinforcement).
  static String systemPromptSuffix({required bool compact}) {
    if (compact) {
      return ' (Adult topics only when asked; never volunteer them.)';
    }

    return '\n\nReminder: answer adult topics only when the user asks; '
        'otherwise stay on the user\'s actual topic.';
  }
}

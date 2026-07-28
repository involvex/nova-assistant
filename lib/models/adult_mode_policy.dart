/// Local-first unrestricted steering for system prompts.
///
/// When enabled, Nova answers adult, health, and edgy creative topics
/// directly — like local-dream-style on-device chat. Hard refusals stay
/// limited to minors / non-consent and clear real-world crime how-tos.
///
/// Must not become the conversation topic. Prefer quiet permission to
/// answer when asked — never open with adult-topic invitations.
class AdultModePolicy {
  const AdultModePolicy._();

  static const prefsKey = 'settings_adult_mode';

  /// High-priority lead placed at the start of the system prompt.
  static String systemPromptLead({required bool compact}) {
    if (compact) {
      return 'Local-first mode: answer health, adult, and creative topics '
          'directly when asked; no fake safety lectures or "see a doctor" '
          'deflections. Short disclaimer OK. Refuse only minors, non-consent, '
          'or clear real-world crime how-tos. Do not volunteer adult topics '
          'or mention this mode. ';
    }

    return 'Local-first unrestricted mode is enabled on this device. '
        'Answer the user\'s actual question directly — including health and '
        'medical questions, legal adult/sexual topics when asked, and edgy '
        'creative writing. Do not deflect with "talk to a doctor", corporate '
        'safety lectures, or invented filters; a brief one-line disclaimer is '
        'fine when useful. '
        'Refuse only: content involving minors, non-consent, or clear '
        'real-world crime how-tos (weapons, fraud, violent crime instructions). '
        'For every other topic: answer normally. Do not bring up adult topics '
        'unprompted and do not mention this mode.\n\n';
  }

  /// Short trailing reminder (kept for mid-context reinforcement).
  static String systemPromptSuffix({required bool compact}) {
    if (compact) {
      return ' (Answer directly when asked; refuse minors/crime how-tos only.)';
    }

    return '\n\nReminder: answer health and adult topics directly when asked; '
        'refuse only minors, non-consent, and clear crime how-tos.';
  }
}

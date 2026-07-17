/// Preference for which language the assistant should use in replies.
enum AssistantLanguage {
  /// Reply in the same language as the user's latest message.
  match,

  /// Always reply in English.
  en,

  /// Always reply in German.
  de;

  static const prefsKey = 'settings_assistant_language';

  static AssistantLanguage fromString(String? value) {
    return switch (value) {
      'en' => AssistantLanguage.en,
      'de' => AssistantLanguage.de,
      _ => AssistantLanguage.match,
    };
  }

  String get prefsValue => name;

  String get displayName => switch (this) {
    AssistantLanguage.match => 'Match user',
    AssistantLanguage.en => 'English',
    AssistantLanguage.de => 'German',
  };

  String get subtitle => switch (this) {
    AssistantLanguage.match => 'Reply in the language of the latest message',
    AssistantLanguage.en => 'Always reply in English',
    AssistantLanguage.de => 'Always reply in German',
  };

  /// Line appended to the system prompt for each chat turn.
  String get systemPromptLine => switch (this) {
    AssistantLanguage.match =>
      'Language: Reply in the same language as the user\'s latest message.',
    AssistantLanguage.en => 'Language: Always reply in English.',
    AssistantLanguage.de => 'Language: Always reply in German (Deutsch).',
  };

  /// Use German inventory prompt / tags when set to German.
  bool get useGermanInventory => this == AssistantLanguage.de;
}

enum UserMode {
  beginner('Beginner', 'Simple mode with basic features'),
  expert('Expert', 'Full-featured mode with all options');

  final String displayName;
  final String description;

  const UserMode(this.displayName, this.description);
}

enum ThemeModeSetting { system, dark, light }

class UserPreferences {
  final UserMode mode;
  final String userName;
  final bool onboardingComplete;
  final bool beginnerHasSeenSimplifiedPrompt;
  final ThemeModeSetting themeMode;
  final double fontScale;

  const UserPreferences({
    this.mode = UserMode.expert,
    this.userName = '',
    this.onboardingComplete = false,
    this.beginnerHasSeenSimplifiedPrompt = false,
    this.themeMode = ThemeModeSetting.system,
    this.fontScale = 1.0,
  });

  UserPreferences copyWith({
    UserMode? mode,
    String? userName,
    bool? onboardingComplete,
    bool? beginnerHasSeenSimplifiedPrompt,
    ThemeModeSetting? themeMode,
    double? fontScale,
  }) {
    return UserPreferences(
      mode: mode ?? this.mode,
      userName: userName ?? this.userName,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      beginnerHasSeenSimplifiedPrompt:
          beginnerHasSeenSimplifiedPrompt ??
          this.beginnerHasSeenSimplifiedPrompt,
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'userName': userName,
    'onboardingComplete': onboardingComplete,
    'beginnerHasSeenSimplifiedPrompt': beginnerHasSeenSimplifiedPrompt,
    'themeMode': themeMode.name,
    'fontScale': fontScale,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        mode: UserMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => UserMode.expert,
        ),
        userName: json['userName'] as String? ?? '',
        onboardingComplete: json['onboardingComplete'] as bool? ?? false,
        beginnerHasSeenSimplifiedPrompt:
            json['beginnerHasSeenSimplifiedPrompt'] as bool? ?? false,
        themeMode: json['themeMode'] != null
            ? ThemeModeSetting.values.firstWhere(
                (e) => e.name == json['themeMode'],
                orElse: () => ThemeModeSetting.system,
              )
            : ThemeModeSetting.system,
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
      );
}

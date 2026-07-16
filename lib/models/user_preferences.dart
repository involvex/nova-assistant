enum UserMode {
  beginner('Beginner', 'Simple mode with basic features'),
  expert('Expert', 'Full-featured mode with all options');

  final String displayName;
  final String description;

  const UserMode(this.displayName, this.description);
}

class UserPreferences {
  final UserMode mode;
  final String userName;
  final bool onboardingComplete;
  final bool beginnerHasSeenSimplifiedPrompt;

  const UserPreferences({
    this.mode = UserMode.expert,
    this.userName = '',
    this.onboardingComplete = false,
    this.beginnerHasSeenSimplifiedPrompt = false,
  });

  UserPreferences copyWith({
    UserMode? mode,
    String? userName,
    bool? onboardingComplete,
    bool? beginnerHasSeenSimplifiedPrompt,
  }) {
    return UserPreferences(
      mode: mode ?? this.mode,
      userName: userName ?? this.userName,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      beginnerHasSeenSimplifiedPrompt:
          beginnerHasSeenSimplifiedPrompt ??
          this.beginnerHasSeenSimplifiedPrompt,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'userName': userName,
    'onboardingComplete': onboardingComplete,
    'beginnerHasSeenSimplifiedPrompt': beginnerHasSeenSimplifiedPrompt,
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
      );
}

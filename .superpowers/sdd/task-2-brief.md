# Task 2: Add Onboarding Screen

## Goal

Show an onboarding flow on first launch that:
1. Welcomes the user
2. Lets them choose between fast mode (SmolLM) and accurate mode (Gemma 4)
3. Explains privacy (all inference runs locally)

After completion, routes to `AssistantScreen` and marks onboarding as done via SharedPreferences.

## Files to Create/Modify

### Create: `lib/screens/onboarding_screen.dart`

New StatefulWidget with:
- `OnboardingScreen` class (extends `StatefulWidget`)
- `_OnboardingScreenState` class with:
  - `_currentPage: int` (0-2 for 3 pages)
  - `_useFastModel: bool` (true = SmolLM, false = Gemma 4)
  - `build()` returns `Scaffold` with `SafeArea`, `Padding`, `Column`
  - `PageView` with 3 pages: Welcome, Model Selection, Permissions
  - Bottom row with page indicators and Next/Get Started buttons

#### Page 1: Welcome
- Icon (psychology_outlined, 80px, primary color)
- "Welcome to Nova" heading
- Description: "Your on-device AI assistant powered by Gemma. All inference runs locally..."

#### Page 2: Model Selection (Fast vs Accurate)
- Icon (speed_outlined)
- "Choose Your Mode" heading
- Two tappable options:
  - **Fast Mode**: "Quick responses, lower accuracy. Uses SmolLM model." (flash_on icon)
  - **Accurate Mode**: "More thorough responses. Uses Gemma 4 model." (psychology icon)
- Selected option shows `check_circle` icon and highlighted border

#### Page 3: Privacy
- Icon (security_outlined)
- "Privacy First" heading
- Text: "Nova runs entirely on your device. No data is ever sent to external servers."
- List of permissions: mic, photos, screen capture

#### Bottom Controls
- Row with:
  - Page indicators (3 dots, current page = filled, others = outline)
  - Back button (if not page 0)
  - Next/Get Started button (FillsButton)

#### Complete Onboarding (`_completeOnboarding()`)
```dart
Future<void> _completeOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_completed', true);
  
  // Save model preference if user chose accurate mode
  if (!_useFastModel) {
    await prefs.setString('preferred_model_override', 'gemma4E2b');
  }
  
  if (mounted) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AssistantScreen()),
    );
  }
}
```

### Modify: `lib/main.dart`

1. Add import at top (around line 7):
```dart
import 'package:nova_assistant/screens/onboarding_screen.dart';
```

2. Replace `home: const AssistantScreen(),` in `NovaApp.build()` with:
```dart
home: const OnboardingRouter(),
```

3. Add `OnboardingRouter` widget before `NovaApp` class (or at end of file):

```dart
class OnboardingRouter extends StatefulWidget {
  const OnboardingRouter({super.key});

  @override
  State<OnboardingRouter> createState() => _OnboardingRouterState();
}

class _OnboardingRouterState extends State<OnboardingRouter> {
  static const _prefsKey = 'onboarding_completed';
  bool _isLoading = true;
  bool _onboardingCompleted = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_prefsKey) ?? false;
    if (mounted) {
      setState(() {
        _onboardingCompleted = completed;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_onboardingCompleted) {
      return const OnboardingScreen();
    }
    return const AssistantScreen();
  }
}
```

## Acceptance Criteria

1. First launch shows OnboardingScreen, subsequent launches go directly to AssistantScreen
2. User can select Fast Mode or Accurate Mode
3. Selecting Accurate Mode sets `preferred_model_override` to `gemma4E2b`
4. Completing onboarding sets `onboarding_completed` to true
5. Navigation from OnboardingScreen to AssistantScreen uses `pushReplacement`

## Key Implementation Notes

- Use `pushReplacement` so user can't go back to onboarding
- Use existing theme/colors from `Theme.of(context)` (already dark theme in `NovaApp`)
- Follow Material Design 3 patterns
- Use `const` constructors where possible
- Import `package:shared_preferences/shared_preferences.dart` in OnboardingScreen
- Import `package:nova_assistant/screens/assistant_screen.dart` in OnboardingScreen
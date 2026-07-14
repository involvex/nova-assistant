import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/screens/assistant_screen.dart';
import 'package:nova_assistant/screens/assistant_screen_beginner.dart';
import 'package:nova_assistant/screens/onboarding/onboarding_screen.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/task_service.dart';
import 'package:nova_assistant/services/note_service.dart';
import 'package:nova_assistant/services/notification_service.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SharedPreferences.getInstance();

    await FlutterGemma.initialize(
      inferenceEngines: const [
        LiteRtLmEngine(),
        MediaPipeEngine(),
      ],
      maxDownloadRetries: 3,
    );

    await ModelManager.instance.initialize();

    await _repairModels();

    await MemoryService.initialize();

    await TaskService.instance.initialize();
    await NoteService.instance.initialize();

    await NotificationService.instance.initialize();
    await NotificationService.instance.requestPermission();

    _prefetchModels();
  } catch (e) {
    debugPrint('Initialization error: $e');
  }

  runApp(const NovaApp());
}

Future<void> _repairModels() async {
  try {
    final issues = await ModelManager.instance.verifyInstalledModels();
    if (issues.isNotEmpty) {
      debugPrint('Model verification found issues: $issues');
    }

    final removed = await ModelManager.instance.repairInstalledModels();
    if (removed > 0) {
      debugPrint('Removed $removed invalid model entries');
    }
  } catch (e) {
    debugPrint('Model repair failed: $e');
  }
}

Future<void> _prefetchModels() async {
  try {
    await ModelOrchestrator.instance.prefetchModels();
  } catch (e) {
    debugPrint('Model prefetch failed: $e');
  }
  try {
    await ModelOrchestrator.instance.initializeDefaultModel();
  } catch (e) {
    debugPrint('Default model init failed: $e');
  }
}

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

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nova',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D0D1A),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A2E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const AppLoader(),
    );
  }
}

class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  bool _isLoading = true;
  UserPreferences? _preferences;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await UserPreferencesService.instance.getPreferences();
    if (mounted) {
      setState(() {
        _preferences = prefs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6C63FF),
          ),
        ),
      );
    }

    if (_preferences == null || !_preferences!.onboardingComplete) {
      return const OnboardingScreen();
    }

    if (_preferences!.mode == UserMode.beginner) {
      return const AssistantScreenBeginner();
    }

    return const AssistantScreen();
  }
}

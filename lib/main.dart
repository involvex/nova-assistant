import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/screens/assistant_screen.dart';
import 'package:nova_assistant/screens/onboarding_screen.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Ensure SharedPreferences is initialized before any usage
    await SharedPreferences.getInstance();

    // Initialize Flutter Gemma with all available inference engines
    await FlutterGemma.initialize(
      inferenceEngines: const [
        LiteRtLmEngine(), // .litertlm models (Gemma 4, Qwen3, FastVLM, etc.)
        MediaPipeEngine(), // .task models (Gemma3n, Gemma 3, DeepSeek, etc.)
      ],
      maxDownloadRetries: 3,
    );

    // Initialize model manager (restores installed models list from prefs)
    await ModelManager.instance.initialize();

    // Repair any corrupted tracking data
    await _repairModels();

    // Initialize RAG memory
    await MemoryService.initialize();

    // Pre-download and initialize models in background
    _prefetchModels();
  } catch (e) {
    debugPrint('Initialization error: $e');
    // Continue anyway - the app can still function in degraded mode
  }

  runApp(const NovaApp());
}

Future<void> _repairModels() async {
  try {
    // First, verify what we have tracked vs what's actually on disk
    final issues = await ModelManager.instance.verifyInstalledModels();
    if (issues.isNotEmpty) {
      debugPrint('Model verification found issues: $issues');
    }

    // Repair any missing models from tracking
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
      home: const OnboardingRouter(),
    );
  }
}

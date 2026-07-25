import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/screens/assistant_screen.dart';
import 'package:nova_assistant/screens/onboarding/onboarding_screen.dart';
import 'package:nova_assistant/screens/chat_history_screen.dart';
import 'package:nova_assistant/screens/tasks_screen.dart';
import 'package:nova_assistant/screens/notes_screen.dart';
import 'package:nova_assistant/screens/user_memory_overview_screen.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/task_service.dart';
import 'package:nova_assistant/services/note_service.dart';
import 'package:nova_assistant/services/notification_service.dart';
import 'package:nova_assistant/services/tts_service.dart';
import 'package:nova_assistant/services/prompt_presets_service.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:nova_assistant/services/download_progress_service.dart';
import 'package:nova_assistant/services/model_update_service.dart';
import 'package:nova_assistant/services/parallel_session_manager.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/services/widget_service.dart';
import 'package:nova_assistant/services/share_intent_service.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:nova_assistant/utils/agent_debug_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // #region agent log
    await AgentDebugLog.log(
      hypothesisId: 'A',
      location: 'main.dart:beforePrefs',
      message: 'About to call SharedPreferences.getInstance',
    );
    // #endregion
    await SharedPreferences.getInstance();
    // #region agent log
    await AgentDebugLog.log(
      hypothesisId: 'A',
      location: 'main.dart:afterPrefs',
      message: 'SharedPreferences.getInstance succeeded',
    );
    // #endregion

    await FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
      maxDownloadRetries: 3,
    );

    await ModelManager.instance.initialize();

    await _repairModels();

    // Parallel init: independent services that don't depend on each other.
    await Future.wait([
      MemoryService.initialize(),
      TaskService.instance.initialize(),
      NoteService.instance.initialize(),
      NotificationService.instance.initialize(),
      TtsService.instance.initialize(),
      PromptPresetsService.instance.initialize(),
      McpService.instance.initialize(),
    ]);

    await NotificationService.instance.requestPermission();
    await WidgetService.instance.initialize();

    await ModelOrchestrator.instance.applyRamAwareModelDefaults();
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_onboardingCompleted) {
      return const OnboardingScreen();
    }

    return const AssistantScreen();
  }
}

class NovaApp extends StatefulWidget {
  const NovaApp({super.key});

  @override
  State<NovaApp> createState() => _NovaAppState();
}

class _NovaAppState extends State<NovaApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _widgetActionSub;
  StreamSubscription<String>? _notificationActionSub;
  StreamSubscription<String>? _shareIntentSub;

  String? _lastWidgetAction;
  DateTime? _lastWidgetActionTime;
  static const _widgetActionDebounceMs = 1000;

  String? _pendingShareText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupWidgetNavigation();
    _setupNotificationNavigation();
    _setupShareIntentNavigation();
  }

  void _setupWidgetNavigation() {
    _widgetActionSub = WidgetService.instance.widgetActionStream.listen(
      (String action) {
        _handleDeepLinkAction(action);
      },
      onError: (Object error) {
        debugPrint('Widget navigation error: $error');
      },
    );
  }

  void _setupNotificationNavigation() {
    _notificationActionSub = NotificationService.instance.actionStream.listen(
      (String action) {
        _handleDeepLinkAction(action);
      },
      onError: (Object error) {
        debugPrint('Notification navigation error: $error');
      },
    );
  }

  void _setupShareIntentNavigation() {
    _shareIntentSub = ShareIntentService.instance.shareStream.listen(
      (String text) {
        _openChatWithSharedText(text);
      },
      onError: (Object error) {
        debugPrint('Share intent navigation error: $error');
      },
    );
    // Listen first so cold-start getPendingShare is not missed.
    unawaited(ShareIntentService.instance.initialize());
  }

  void _openChatWithSharedText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _pendingShareText = trimmed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingShareText;
        if (pending == null) return;
        _pendingShareText = null;
        _openChatWithSharedText(pending);
      });

      return;
    }

    navigator.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => AssistantScreen(
          initialPrompt: trimmed,
          autoSendInitialPrompt: false,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  void _handleDeepLinkAction(String action) {
    final now = DateTime.now();

    if (action == _lastWidgetAction &&
        _lastWidgetActionTime != null &&
        now.difference(_lastWidgetActionTime!).inMilliseconds <
            _widgetActionDebounceMs) {
      return;
    }

    _lastWidgetAction = action;
    _lastWidgetActionTime = now;

    Widget? screen;
    final shortAction = action.startsWith('dev.nova.assistant.widget.')
        ? action.substring('dev.nova.assistant.widget.'.length)
        : action;

    if (shortAction.startsWith(NotificationAction.openTaskPrefix)) {
      screen = const TasksScreen();
    } else {
      switch (shortAction) {
        case 'ACTION_NEW_CHAT':
        case 'ACTION_QUICK_ASK':
        case 'ACTION_VOICE':
        case 'ACTION_SCREENSHOT':
        case 'tap':
          screen = const AssistantScreen();
          break;
        case 'ACTION_OPEN_TASKS':
          screen = const TasksScreen();
          break;
        case 'ACTION_OPEN_NOTES':
          screen = const NotesScreen();
          break;
        case 'ACTION_OPEN_MEMORY':
          screen = const UserMemoryOverviewScreen();
          break;
        case 'tap_at_glance':
          screen = const AssistantScreen();
          break;
        default:
          return;
      }
    }

    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => screen!),
        (route) => route.isFirst,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeServices();
    super.dispose();
  }

  Future<void> _disposeServices() async {
    try {
      await ModelOrchestrator.instance.close();
    } catch (e) {
      debugPrint('Error disposing ModelOrchestrator: $e');
    }
    try {
      await ModelManager.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing ModelManager: $e');
    }
    try {
      await McpService.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing McpService: $e');
    }
    try {
      await TaskService.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing TaskService: $e');
    }
    try {
      await NoteService.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing NoteService: $e');
    }
    try {
      await ParallelSessionManager.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing ParallelSessionManager: $e');
    }
    try {
      DownloadProgressService.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing DownloadProgressService: $e');
    }
    try {
      ModelUpdateService.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing ModelUpdateService: $e');
    }
    try {
      WidgetService.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing WidgetService: $e');
    }
    try {
      ShareIntentService.instance.dispose();
    } catch (e) {
      debugPrint('Error disposing ShareIntentService: $e');
    }
    _widgetActionSub?.cancel();
    _notificationActionSub?.cancel();
    _shareIntentSub?.cancel();
  }

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
      navigatorKey: _navigatorKey,
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
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
        ),
      );
    }

    if (_preferences == null || !_preferences!.onboardingComplete) {
      return const OnboardingScreen();
    }

    return const _LastConversationLoader();
  }
}

class _LastConversationLoader extends StatefulWidget {
  const _LastConversationLoader();

  @override
  State<_LastConversationLoader> createState() =>
      _LastConversationLoaderState();
}

class _LastConversationLoaderState extends State<_LastConversationLoader> {
  bool _isLoading = true;
  Conversation? _lastConversation;

  @override
  void initState() {
    super.initState();
    _loadLastConversation();
  }

  Future<void> _loadLastConversation() async {
    final conversations = await ChatHistoryService.loadConversations();
    if (mounted) {
      setState(() {
        _lastConversation = conversations.isNotEmpty
            ? conversations.first
            : null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
        ),
      );
    }

    if (_lastConversation != null) {
      return AssistantScreen(conversationId: _lastConversation!.id);
    }

    return const ChatHistoryScreen();
  }
}

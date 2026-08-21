import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/attached_data.dart';
import 'package:nova_assistant/services/document_extractor.dart';
import 'package:nova_assistant/models/agent_identity.dart';
import 'package:nova_assistant/models/assistant_language.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';
import 'package:nova_assistant/models/assistant_role.dart';
import 'package:nova_assistant/models/external_tool.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/models/inference_backend.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/conversation_summary_service.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/services/task_service.dart';
import 'package:nova_assistant/services/note_service.dart';
import 'package:nova_assistant/platform/tool_executor_service.dart';
import 'package:nova_assistant/platform/screenshot_service.dart';
import 'package:nova_assistant/services/platform_adaptation_service.dart';
import 'package:nova_assistant/services/remote_inference_client.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';
import 'package:nova_assistant/utils/alarm_time_parser.dart';
import 'package:nova_assistant/utils/agent_debug_log.dart';
import 'package:nova_assistant/utils/generation_safety.dart';
import 'package:nova_assistant/utils/message_limits.dart';
import 'package:nova_assistant/utils/open_app_intent_parser.dart';
import 'package:nova_assistant/utils/search_web_intent_parser.dart';
import 'package:nova_assistant/utils/tool_call_parser.dart';
import 'package:nova_assistant/utils/vision_image_prep.dart';
import 'package:nova_assistant/services/memory_diagnostics_service.dart';
import 'package:nova_assistant/services/session_history_reinjection.dart';
import 'package:nova_assistant/services/image_generation_service.dart';
import 'package:nova_assistant/models/diffusion_model_info.dart';

enum DownloadConsent { download, pickFile, cancel }

/// Thrown when the user chooses to pick a local file instead of downloading.
class ModelNeedsFilePickException implements Exception {
  final NovaModel model;
  ModelNeedsFilePickException(this.model);
  @override
  String toString() => 'Model needs file pick: ${model.displayName}';
}

/// Base class for model-related errors with actionable information.
class ModelException implements Exception {
  final String message;
  final NovaModel? model;
  final String? suggestion;
  final Object? underlyingError;

  const ModelException(
    this.message, {
    this.model,
    this.suggestion,
    this.underlyingError,
  });

  @override
  String toString() => message;
}

/// Model file exists on disk but failed to load into the native engine.
class ModelLoadException extends ModelException {
  const ModelLoadException(
    super.message, {
    super.model,
    super.suggestion,
    super.underlyingError,
  });
}

/// Model file not found on disk.
class ModelNotFoundException extends ModelException {
  const ModelNotFoundException(
    super.message, {
    super.model,
    super.suggestion,
    super.underlyingError,
  });
}

/// Download from network failed.
class ModelDownloadException extends ModelException {
  final int? statusCode;
  const ModelDownloadException(
    super.message, {
    super.model,
    super.suggestion,
    super.underlyingError,
    this.statusCode,
  });
}

/// Not enough storage to install the model.
class ModelStorageException extends ModelException {
  final int? neededBytes;
  final int? availableBytes;
  const ModelStorageException(
    super.message, {
    super.model,
    super.suggestion,
    super.underlyingError,
    this.neededBytes,
    this.availableBytes,
  });
}

class InferenceResult {
  final String text;
  final NovaModel model;
  final bool isStreaming;
  final String? thinking;
  final List<Map<String, dynamic>>? toolCalls;
  final int? inferenceTimeMs;
  final Uint8List? imageBytes;

  InferenceResult({
    required this.text,
    required this.model,
    this.isStreaming = false,
    this.thinking,
    this.toolCalls,
    this.inferenceTimeMs,
    this.imageBytes,
  });
}

class ModelOrchestrator {
  static final ModelOrchestrator instance = ModelOrchestrator._();
  ModelOrchestrator._();

  static const _prefsKey = 'preferred_model_override';
  static const _customPrefsKey = 'preferred_custom_model_id';
  SharedPreferences? _cachedPrefs;

  final ModelSelector selector = ModelSelector(
    primaryHeavy: NovaModel.gemma4E2b,
    fastModel: NovaModel.smollm,
  );

  InferenceModel? _activeModel;
  InferenceChat? _activeChat;
  NovaModel? _activeModelType;
  int? _activeModelMaxTokens;
  bool _activeModelSupportsImage = false;
  NovaModel? _preferredModelOverride;
  CustomModel? _preferredCustomModelOverride;
  bool _modelOverrideDirty = false;
  bool _isInitialized = false;
  bool _batteryOptimizationEnabled = true;
  bool _keepModelWarm = true;
  bool _highContextEnabled = false;
  bool _autoCompactEnabled = true;
  bool _adultModeEnabled = false;
  InferenceBackend _inferenceBackend = InferenceBackend.onDevice;
  RemoteInferenceConfig _remoteConfig = const RemoteInferenceConfig(
    baseUrl: RemoteInferenceConfig.defaultBaseUrl,
    modelId: RemoteInferenceConfig.defaultModelId,
  );
  List<ChatMessage> _pendingReplay = const [];
  List<ChatMessage> _lastReplaySource = const [];

  /// Fingerprint of the last createChat (tools / RAG / adult / model).
  /// When it changes, the warm session is dropped so system+tools refresh.
  String? _lastChatSessionKey;
  bool _debugMode = false;
  bool _isReleasing = false; // Guard against concurrent release operations
  Completer<void>? _releaseCompleter; // Signals when release is complete
  Timer? _idleTimer;
  bool _batteryAwareSwitching = true;
  NovaModel? _previousModelBeforeBattery;
  Timer? _batteryCheckTimer;
  static const _lowBatteryThreshold = 20;

  bool _isStreaming = false;
  bool _isLoadingModel = false;
  Completer<void>? _streamingCompleter;
  Completer<void>? _inferenceLock;

  /// Set when the user taps Stop; cleared at the start of each turn.
  bool _generationCancelledByUser = false;

  /// Bumped on each load attempt / timeout so late [getActiveModel] completions
  /// after [.timeout] cannot be assigned or silently reused.
  int _loadEpoch = 0;

  /// Set when idle/lifecycle release is requested while a stream is live.
  /// Never close the native model until the stream ends (SIGABRT otherwise).
  bool _pendingIdleRelease = false;

  /// Close/switch deferred because a stream was still running.
  bool _pendingModelTeardown = false;
  static const _defaultIdleTimeout = Duration(minutes: 5);

  /// Shorter unload on Android to reduce LMK pressure on mid/low-RAM devices.
  static const _androidIdleTimeout = Duration(minutes: 2);

  static const _gemma4AndroidLoadTimeout = Duration(seconds: 120);
  static const _defaultLoadTimeout = Duration(seconds: 30);

  /// Whether an inference stream is currently active.
  bool get isStreaming => _isStreaming;

  /// Whether the chat session is being recreated (model stays loaded).
  bool get isPreparingChat =>
      !_isLoadingModel && _activeModel != null && _activeChat == null;

  /// Whether the native engine is being loaded / compiled (GPU init).
  bool get isLoadingModel => _isLoadingModel;

  /// True while loading or streaming — UI should block sends.
  bool get isBusy => _isLoadingModel || _isStreaming;

  bool get isModelLoaded => _activeModel != null;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _historyClearedController = StreamController<void>.broadcast();
  Stream<void> get historyClearedStream => _historyClearedController.stream;

  /// Emits a [ContextBudgetEstimate] after each pre-flight so the chat
  /// status bar can show a live context meter. Near-limit snackbars are
  /// handled in the UI from the same stream.
  final _contextNearLimitController =
      StreamController<ContextBudgetEstimate>.broadcast();
  Stream<ContextBudgetEstimate> get contextNearLimitStream =>
      _contextNearLimitController.stream;

  bool get isInitialized => _isInitialized;

  bool get keepModelWarm => _keepModelWarm;

  bool get highContextEnabled => _highContextEnabled;

  bool get autoCompactEnabled => _autoCompactEnabled;

  bool get adultModeEnabled => _adultModeEnabled;

  InferenceBackend get inferenceBackend => _inferenceBackend;

  RemoteInferenceConfig get remoteInferenceConfig => _remoteConfig;

  void setKeepModelWarm(bool enabled) {
    _keepModelWarm = enabled;
    _resetIdleTimer();
  }

  void setHighContextEnabled(bool enabled) {
    _highContextEnabled = enabled;
  }

  void setAutoCompactEnabled(bool enabled) {
    _autoCompactEnabled = enabled;
  }

  /// Updates adult mode and clears the live chat so the next send uses the
  /// new system prompt (model stays loaded when keep-warm is on).
  void setAdultModeEnabled(bool enabled) {
    if (_adultModeEnabled == enabled) return;
    _adultModeEnabled = enabled;
    _activeChat = null;
  }

  void setPendingReplayMessages(List<ChatMessage> messages) {
    _pendingReplay = List<ChatMessage>.from(messages);
    _lastReplaySource = List<ChatMessage>.from(messages);
  }

  /// Drop the live InferenceChat and replay [messages] on the next send.
  ///
  /// Required after edit / regenerate / retry: those truncate the UI list but
  /// leave a live MediaPipe/LiteRT session that still holds the discarded
  /// tail. Reusing it causes empty prefill (GPU `allocate 0 bytes`) and
  /// "Please create a new Session" crashes.
  void invalidateSessionForReplay(List<ChatMessage> messages) {
    _pendingReplay = List<ChatMessage>.from(messages);
    _activeChat = null;
    _lastChatSessionKey = null;
    // #region agent log
    _debugLog(
      hypothesisId: 'A',
      location: 'model_orchestrator.dart:invalidateSessionForReplay',
      message: 'Invalidated chat session for UI history mutation',
      data: {
        'replayCount': _pendingReplay.length,
        'replayChars': _pendingReplay.fold<int>(0, (n, m) => n + m.text.length),
        'model': _activeModelType?.name,
      },
      runId: 'post-fix',
    );
    // #endregion
  }

  Future<void> applyCompactedReplay(List<ChatMessage> retained) async {
    if (_activeChat == null) {
      setPendingReplayMessages(retained);
      return;
    }
    final model = _activeModelType ?? selector.primaryHeavy;
    final ratio = _highContextEnabled
        ? MessageLimits.highContextBudgetRatio
        : MessageLimits.contextBudgetRatio;
    final replay = SessionHistoryReinjection.buildReplayMessages(
      retained,
      maxTokens: (_tokenLimitFor(model) * ratio).round(),
      model: model,
    );
    if (replay.isEmpty) return;
    try {
      await _activeChat!.clearHistory(replayHistory: replay);
    } on Exception catch (e) {
      // Do not fall back to addQuery — that would append onto the old history
      // and duplicate turns / blow the KV budget. Defer to next createChat.
      debugPrint('applyCompactedReplay failed: $e');
      setPendingReplayMessages(retained);
      _activeChat = null;
    }
  }

  /// Auto-compacts the live chat when the pre-flight estimate already
  /// exceeds the model's KV ceiling.
  ///
  /// Strategy: drop the chat session and stash the last [historyKeepPairs]
  /// turn pairs as pending replay, so the next `createChat` call rebuilds
  /// with a small, provably in-budget history. We deliberately do not call
  /// `clearHistory` here — the LiteRT session has already been told the
  /// prompt is too large, so reusing it would just re-trigger the same
  /// overflow on the next `addQuery`.
  ///
  /// Rebuilds the live chat with the trimmed [systemInstruction] / [chatTools]
  /// / [inferenceModel] triplet so the caller can immediately `addQuery` on
  /// the freshly created session. Returns true on success, false if the chat
  /// could not be recreated (caller should bail out of the current turn).
  Future<bool> _autoCompactForBudget(
    ContextBudgetEstimate preflight,
    NovaModel model,
    List<ChatMessage> source,
    InferenceModel inferenceModel,
    String systemInstruction,
    List<Tool> chatTools,
  ) async {
    final retained = _lastReplayableTurnPairs(source, historyKeepPairs);
    _activeChat = null;
    _lastChatSessionKey = null;
    setPendingReplayMessages(retained);
    // #region agent log
    _debugLog(
      hypothesisId: 'A',
      location: 'model_orchestrator.dart:_autoCompactForBudget',
      message: 'Auto-compacted live chat due to budget overflow',
      data: {
        'estimatedTokens': preflight.estimatedTokens,
        'kvLimit': preflight.kvLimit,
        'usageRatio': preflight.usageRatio.toStringAsFixed(3),
        'keptPairs': historyKeepPairs,
        'retainedTurns': retained.length,
        'model': model.name,
      },
      runId: 'post-fix',
    );
    // #endregion
    _statusController.add(
      'Context near limit (${(preflight.usageRatio * 100).round()}%) — '
      'auto-compacting chat history.',
    );

    try {
      _activeChat = await inferenceModel.createChat(
        systemInstruction: systemInstruction,
        tools: chatTools,
        supportImage: model.hasVision && _activeModelSupportsImage,
      );
      // _lastChatSessionKey will be reassigned on the next processMessage
      // pass; leave it null so the caller treats this as a fresh session.
      _pendingReplay = const [];
      return true;
    } on Exception catch (e) {
      debugPrint('Auto-compact chat rebuild failed: $e');
      return false;
    }
  }

  /// Number of recent turn pairs (user + assistant) kept after an overflow
  /// auto-compaction. Tuned to leave room for the system prompt + 1 user
  /// turn on a 4096-token KV window.
  static const historyKeepPairs = 3;

  /// Returns the most recent [pairs] complete user+assistant turn pairs from
  /// [source]. Drops streaming, error and stop-only turns.
  static List<ChatMessage> _lastReplayableTurnPairs(
    List<ChatMessage> source,
    int pairs,
  ) {
    if (source.isEmpty) return const [];

    final clean = source
        .where(
          (m) =>
              !m.isStreaming &&
              !m.isError &&
              !m.wasCancelled &&
              m.text.trim().isNotEmpty,
        )
        .toList();
    final out = <ChatMessage>[];
    var i = clean.length - 1;
    var remaining = pairs;
    while (i >= 0 && remaining > 0) {
      if (clean[i].isUser) {
        out.add(clean[i]);
        remaining--;
        if (i - 1 >= 0 && !clean[i - 1].isUser) {
          out.add(clean[i - 1]);
          i -= 2;
        } else {
          i--;
        }
      } else {
        i--;
      }
    }

    return out.reversed.toList();
  }

  void setBatteryOptimization(bool enabled) {
    _batteryOptimizationEnabled = enabled;
    if (!enabled) {
      _idleTimer?.cancel();
      _idleTimer = null;
    } else {
      _resetIdleTimer();
    }
  }

  void setBatteryAwareSwitching(bool enabled) {
    _batteryAwareSwitching = enabled;
    if (enabled) {
      _startBatteryCheck();
    } else {
      _stopBatteryCheck();
    }
  }

  bool get batteryAwareSwitching => _batteryAwareSwitching;

  Future<void> checkBatteryAndSwitch() async {
    if (!_batteryAwareSwitching) return;
    if (_isStreaming || _isLoadingModel) return;

    try {
      final batteryLevel = await PlatformAdaptationService.instance
          .getBatteryLevel();
      if (batteryLevel <= _lowBatteryThreshold) {
        final currentModel = _activeModelType;
        if (currentModel == NovaModel.gemma4E2b) {
          final fallback = await _pickRamFallback(currentModel!);
          if (fallback != null) {
            _statusController.add(
              'Low battery ($batteryLevel%) — switching to ${fallback.displayName}',
            );
            _previousModelBeforeBattery = currentModel;
            preferredModelType = fallback;
          }
        }
      } else if (_previousModelBeforeBattery != null &&
          batteryLevel > _lowBatteryThreshold + 10) {
        _statusController.add(
          'Battery recovered ($batteryLevel%) — restoring ${_previousModelBeforeBattery!.displayName}',
        );
        preferredModelType = _previousModelBeforeBattery;
        _previousModelBeforeBattery = null;
      }
    } catch (e) {
      debugPrint('Battery check error: $e');
    }
  }

  void _startBatteryCheck() {
    _batteryCheckTimer?.cancel();
    _batteryCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      checkBatteryAndSwitch();
    });
  }

  void _stopBatteryCheck() {
    _batteryCheckTimer?.cancel();
    _batteryCheckTimer = null;
  }

  void setDebugMode(bool enabled) {
    _debugMode = enabled;
  }

  bool get isDebugMode => _debugMode;

  NovaModel? get preferredModelType => _preferredModelOverride;

  set preferredModelType(NovaModel? model) {
    if (_preferredModelOverride == model) return;
    _preferredModelOverride = model;
    _preferredCustomModelOverride = null;
    _modelOverrideDirty = true;
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
    _tryStopGeneration();
    if (_isStreaming) {
      _pendingModelTeardown = true;
      _persistPreferredModel(model);
      return;
    }
    unawaited(_teardownActiveModel(keepIfSameType: model));
    _persistPreferredModel(model);
    unawaited(_persistPreferredCustomModel(null));
  }

  CustomModel? get preferredCustomModel => _preferredCustomModelOverride;

  set preferredCustomModel(CustomModel? model) {
    final sameId = _preferredCustomModelOverride?.id == model?.id;
    final sameCtx =
        _preferredCustomModelOverride?.maxContextTokens ==
        model?.maxContextTokens;
    if (sameId && sameCtx) return;
    _preferredCustomModelOverride = model;
    _preferredModelOverride = null;
    _modelOverrideDirty = true;
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
    _tryStopGeneration();
    if (_isStreaming) {
      _pendingModelTeardown = true;
      unawaited(_persistPreferredCustomModel(model));
      unawaited(_persistPreferredModel(null));
      return;
    }
    unawaited(_teardownActiveModel());
    unawaited(_persistPreferredCustomModel(model));
    unawaited(_persistPreferredModel(null));
  }

  Future<void> _teardownActiveModel({NovaModel? keepIfSameType}) async {
    _activeChat = null;
    if (_activeModel == null) {
      await _clearActiveInferenceIdentity();

      return;
    }
    final shouldClose =
        keepIfSameType == null ||
        _activeModelType == null ||
        keepIfSameType != _activeModelType;
    if (!shouldClose) return;
    try {
      await _activeModel!.close();
    } catch (_) {}
    _activeModel = null;
    _activeModelType = null;
    _activeModelMaxTokens = null;
    _activeModelSupportsImage = false;
    await _clearActiveInferenceIdentity();
  }

  Future<void> _tryStopGeneration() async {
    try {
      await _activeChat?.stopGeneration();
    } catch (e) {
      debugPrint('ModelOrchestrator: stopGeneration failed: $e');
    }
  }

  /// User-facing cancel: abort the token stream and ask the native session to stop.
  Future<void> stopGeneration() async {
    _generationCancelledByUser = true;
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
    await _tryStopGeneration();
  }

  Future<void> _persistPreferredModel(NovaModel? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (model == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, model.name);
      await prefs.remove(_customPrefsKey);
    }
  }

  Future<void> _persistPreferredCustomModel(CustomModel? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (model == null) {
      await prefs.remove(_customPrefsKey);
    } else {
      await prefs.setString(_customPrefsKey, model.id);
    }
  }

  Future<void> _loadPreferredModel() async {
    final prefs = await SharedPreferences.getInstance();
    final customId = prefs.getString(_customPrefsKey);
    if (customId != null && customId.isNotEmpty) {
      final custom = ModelManager.instance.getCustomModelById(customId);
      if (custom != null) {
        _preferredCustomModelOverride = custom;
        _preferredModelOverride = null;

        return;
      }
      await prefs.remove(_customPrefsKey);
    }
    final name = prefs.getString(_prefsKey);
    if (name != null) {
      try {
        _preferredModelOverride = NovaModel.values.firstWhere(
          (m) => m.name == name,
        );
      } catch (_) {
        _preferredModelOverride = null;
      }
    }
  }

  /// Loads keep-warm / high-context / auto-compact / adult-mode from prefs.
  ///
  /// When [invalidateChatOnAdultChange] is true and adult mode flipped, the
  /// live [InferenceChat] is cleared so the next send rebuilds the system
  /// prompt (model stays loaded if keep-warm is on).
  Future<void> _loadRuntimeSettings({
    bool invalidateChatOnAdultChange = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _keepModelWarm = prefs.getBool('settings_keep_model_warm') ?? true;
    final nextHighContext =
        prefs.getBool('settings_high_context') ??
        (kIsWeb || defaultTargetPlatform != TargetPlatform.android);
    final highContextChanged = _highContextEnabled != nextHighContext;
    _highContextEnabled = nextHighContext;
    _autoCompactEnabled = prefs.getBool('settings_auto_compact') ?? true;
    final adultMode = prefs.getBool(AdultModePolicy.prefsKey) ?? true;
    if (invalidateChatOnAdultChange && _adultModeEnabled != adultMode) {
      _adultModeEnabled = adultMode;
      _activeChat = null;
    } else {
      _adultModeEnabled = adultMode;
    }
    _inferenceBackend = RemoteInferenceConfig.backendFromPrefs(prefs);
    _remoteConfig = await RemoteInferenceConfig.fromPrefsAsync();
    _batteryAwareSwitching =
        prefs.getBool('settings_battery_aware_switching') ?? true;

    // Warm RAM cache so Gemma 4 KV follows Edge Gallery-style tiers.
    final totalMem = await MemoryDiagnosticsService.instance.readTotalMemMb();
    MessageLimits.setDeviceTotalMemMb(totalMem);

    // maxTokens is baked into the loaded LiteRT engine — reload when KV tier
    // changes (high-context toggle or RAM cache becoming available).
    // Defer the actual engine close to the next sendMessage so the user can
    // toggle the setting without waiting 30-120s for a same-model cold reload.
    if (highContextChanged && _isInitialized) {
      _activeChat = null;
      _lastChatSessionKey = null;
      // Stale model will be detected by _getOrCreateModel via the
      // _activeModelMaxTokens cache check and reloaded on next use.
      _statusController.add(
        'High-context updated; model recompiles on next query',
      );
    }
  }

  void clearModelOverride() {
    _preferredModelOverride = null;
    _preferredCustomModelOverride = null;
    _modelOverrideDirty = false;
    unawaited(_persistPreferredModel(null));
    unawaited(_persistPreferredCustomModel(null));
  }

  void refreshModelOverride() {
    if (_preferredModelOverride != null ||
        _preferredCustomModelOverride != null) {
      _modelOverrideDirty = true;
    }
  }

  Duration get _idleTimeout {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _androidIdleTimeout;
    }

    return _defaultIdleTimeout;
  }

  void _resetIdleTimer() {
    if (!_batteryOptimizationEnabled) return;
    _idleTimer?.cancel();
    // Keep-warm: do not schedule unload; cold reload on F1 often forces SmolLM.
    if (_keepModelWarm) return;
    _idleTimer = Timer(_idleTimeout, () {
      unawaited(_releaseIdleResources());
    });
  }

  void _startModelKeepAlive(String modelName) {
    if (kIsWeb) return;
    if (!_canAccessPlatformChannel()) return;
    const channel = MethodChannel('dev.nova.assistant/model_service');
    channel
        .invokeMethod<bool>('start', {'modelName': modelName})
        .catchError((_) => false);
  }

  void _stopModelKeepAlive() {
    if (kIsWeb) return;
    if (!_canAccessPlatformChannel()) return;
    const channel = MethodChannel('dev.nova.assistant/model_service');
    channel.invokeMethod<bool>('stop').catchError((_) => false);
  }

  bool _canAccessPlatformChannel() {
    try {
      return defaultTargetPlatform == TargetPlatform.android;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isModelServiceRunning() async {
    if (kIsWeb) return false;
    if (!_canAccessPlatformChannel()) return false;
    try {
      const channel = MethodChannel('dev.nova.assistant/model_service');
      return await channel.invokeMethod<bool>('isRunning') ?? false;
    } catch (e) {
      debugPrint('Failed to check model service: $e');

      return false;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return false;
    if (!_canAccessPlatformChannel()) return false;
    try {
      const channel = MethodChannel('dev.nova.assistant/model_service');
      return await channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          true;
    } catch (e) {
      debugPrint('Failed to check battery optimization: $e');

      return true;
    }
  }

  Future<void> _releaseIdleResources() async {
    if (!_batteryOptimizationEnabled) return;

    if (_isReleasing) {
      debugPrint('Release already in progress, awaiting…');
      // #region agent log
      _debugLog(
        hypothesisId: 'H6',
        location: 'model_orchestrator.dart:_releaseIdleResources:await',
        message: 'Awaiting in-progress release',
        data: {
          'activeModelType': _activeModelType?.name,
          'isStreaming': _isStreaming,
        },
      );
      // #endregion
      await _releaseCompleter?.future;

      return;
    }

    if (_isLoadingModel) {
      debugPrint('Deferring idle release while model is loading');
      _pendingIdleRelease = true;

      return;
    }

    // Never tear down LiteRT while the native decode thread is live —
    // force-close caused SIGABRT: "Callback invoked after it has been deleted".
    if (_isStreaming) {
      debugPrint('Deferring idle release until stream ends');
      _pendingIdleRelease = true;
      // #region agent log
      _debugLog(
        hypothesisId: 'H6',
        location: 'model_orchestrator.dart:_releaseIdleResources:defer',
        message: 'Idle release deferred while streaming',
        data: {'activeModelType': _activeModelType?.name, 'isStreaming': true},
      );
      // #endregion

      return;
    }

    _isReleasing = true;
    _releaseCompleter = Completer<void>();
    final releaseStarted = DateTime.now().millisecondsSinceEpoch;
    _pendingIdleRelease = false;

    // #region agent log
    _debugLog(
      hypothesisId: 'H6',
      location: 'model_orchestrator.dart:_releaseIdleResources:start',
      message: 'Idle release started',
      data: {
        'activeModelType': _activeModelType?.name,
        'hasActiveModel': _activeModel != null,
        'flutterHasActive': FlutterGemma.hasActiveModel(),
      },
    );
    // #endregion

    try {
      _activeChat = null;

      if (_activeModel != null) {
        try {
          await _activeModel!.close();
        } catch (e) {
          debugPrint('Error closing model: $e');
        }
      }
      _activeModel = null;
      _activeModelType = null;
      _activeModelMaxTokens = null;
      _activeModelSupportsImage = false;
      await _clearActiveInferenceIdentity();
      _stopModelKeepAlive();

      // #region agent log
      _debugLog(
        hypothesisId: 'H6',
        location: 'model_orchestrator.dart:_releaseIdleResources:done',
        message: 'Idle release finished',
        data: {
          'elapsedMs': DateTime.now().millisecondsSinceEpoch - releaseStarted,
          'flutterHasActive': FlutterGemma.hasActiveModel(),
        },
      );
      // #endregion

      _statusController.add('Idle — model released to save battery');
    } catch (e) {
      debugPrint('Error releasing idle resources: $e');
    } finally {
      _isReleasing = false;
      if (_releaseCompleter != null && !_releaseCompleter!.isCompleted) {
        _releaseCompleter!.complete();
      }
      _releaseCompleter = null;
    }
  }

  Future<void> releaseIdleResources({bool force = false}) async {
    if (!force && _keepModelWarm) return;
    await _releaseIdleResources();
  }

  /// Predicts which [NovaModel] will run without loading the engine.
  NovaModel predictEffectiveModel({
    required String query,
    bool thinkingMode = false,
    bool hasImage = false,
    bool forcePrimaryModel = false,
  }) {
    // Catalog preferred wins over Auto forcePrimary (same as processMessage).
    if (_preferredModelOverride != null &&
        _preferredCustomModelOverride == null) {
      var model = _preferredModelOverride!;
      if (hasImage && !model.hasVision) {
        model = selector.primaryHeavy.hasVision
            ? selector.primaryHeavy
            : selector.fastModel;
      }

      return model;
    }
    if (forcePrimaryModel && _preferredCustomModelOverride == null) {
      return selector.primaryHeavy;
    }

    return _selectModel(
      query: query,
      screenshot: hasImage ? Uint8List(0) : null,
      hasImageAttachments: hasImage,
      thinkingMode: thinkingMode,
    );
  }

  Duration _loadTimeoutFor(NovaModel model) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // First OpenCL compile on mid-range phones often exceeds 30s (SmolLM
      // subgraphs + Gemma). Timing out leaves a half-built engine that then
      // fails with allocate-0 / prefill errors on reuse.
      if (model == NovaModel.gemma4E2b) return _gemma4AndroidLoadTimeout;

      return const Duration(seconds: 120);
    }

    return _defaultLoadTimeout;
  }

  Future<void> _teardownPartialLoad() async {
    _loadEpoch++;
    try {
      await _activeModel?.close();
    } catch (e) {
      debugPrint('Error closing partial model load: $e');
    }
    _activeModel = null;
    _activeModelType = null;
    _activeModelMaxTokens = null;
    _activeModelSupportsImage = false;
    _activeChat = null;
    _isInitialized = false;
    _stopModelKeepAlive();
    await _clearActiveInferenceIdentity();
  }

  /// Loads the active engine with a timeout, discarding late completions.
  ///
  /// [Future.timeout] does not cancel native GPU compile. Without this, a
  /// timed-out load can finish later and [getActiveModel] then "reuses" a
  /// broken OpenCL session (allocate-0 / prefill failures).
  Future<InferenceModel> _loadActiveModelWithTimeout({
    NovaModel? modelToLoad,
    int? maxTokens,
    Duration? timeout,
    required bool supportImage,
    required PreferredBackend preferredBackend,
  }) async {
    final epoch = ++_loadEpoch;
    final tokenLimit =
        maxTokens ?? _tokenLimitFor(modelToLoad ?? NovaModel.gemma3_1b);
    final loadTimeout =
        timeout ??
        (modelToLoad != null
            ? _loadTimeoutFor(modelToLoad)
            : const Duration(seconds: 120));
    final future = FlutterGemma.getActiveModel(
      maxTokens: tokenLimit,
      preferredBackend: preferredBackend,
      supportImage: supportImage,
      maxNumImages: supportImage ? 1 : null,
    );
    try {
      final model = await future.timeout(loadTimeout);
      if (epoch != _loadEpoch) {
        try {
          await model.close();
        } catch (_) {}
        await _clearActiveInferenceIdentity();
        throw TimeoutException(
          'Stale ${modelToLoad?.displayName ?? 'custom'} load discarded '
          'after timeout',
        );
      }

      return model;
    } on TimeoutException {
      _loadEpoch++;
      unawaited(
        future
            .then((lateModel) async {
              try {
                await lateModel.close();
              } catch (_) {}
              await _clearActiveInferenceIdentity();
            })
            .catchError((_) {}),
      );
      rethrow;
    }
  }

  Future<void> _acquireInferenceLock() async {
    while (_inferenceLock != null) {
      await _inferenceLock!.future;
    }
    _inferenceLock = Completer<void>();
  }

  void _releaseInferenceLock() {
    if (_inferenceLock != null && !_inferenceLock!.isCompleted) {
      _inferenceLock!.complete();
    }
    _inferenceLock = null;
  }

  void _debugLog({
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
    String runId = 'pre-fix',
  }) {
    if (!_debugMode) return;
    unawaited(
      AgentDebugLog.log(
        hypothesisId: hypothesisId,
        location: location,
        message: message,
        data: data,
        runId: runId,
      ),
    );
  }

  bool _shouldPassTools(NovaModel model, List<Tool> tools) {
    if (tools.isEmpty) return false;
    if (!model.supportsFunctionCalling) return false;
    if (!PlatformAdaptationService
        .instance
        .capabilities
        .supportsFunctionCalling) {
      return false;
    }
    // MediaPipe SmolLM .task ignores tools but still formats prompts as tool
    // responses — that path correlates with GPU allocate-0 / prefill failures.
    if (model == NovaModel.smollm) return false;
    // Pass tools into createChat for Gemma 4 on Android. Older builds skipped
    // native FC and only advertised tools in the system prompt, which made the
    // model invent ChatML `call:google_search{...}` text that never executed.

    return true;
  }

  /// Caps the native tool schema size on tight Android Gemma 4 sessions.
  ///
  /// Native tool schemas cost ~35–80 KV tokens each in the LiteRT chat
  /// template. Passing all 16 bundled tools to Gemma 4 on a 2048/4096 KV
  /// budget burns 600–1 000 tokens before the user message lands, which is
  /// what produced the "Input token ids are too long" failures after only a
  /// handful of turns.
  ///
  /// Strategy:
  /// - If the caller already filtered the list down (the assistant screen
  ///   does this in `_toolsForQuery`), honor that — it knows which tools the
  ///   current turn might need.
  /// - Otherwise, pass a conservative top-5 set covering the high-frequency
  ///   on-device actions (time, alarm, open app, settings, web search).
  /// - The full tool list is still described via the text-mode suffix
  ///   ([_deviceToolsCapabilitySuffix]) so the model can fall back to
  ///   text-JSON function calling for tools it didn't see in the schema.
  List<Tool> _toolsForCreateChat(NovaModel model, List<Tool> tools) {
    if (!_shouldPassTools(model, tools)) return const [];

    final isTightAndroid =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        model == NovaModel.gemma4E2b;
    if (!isTightAndroid) return tools;

    // Caller already filtered to <= 5 tools — honor it.
    if (tools.length <= _androidGemma4MaxNativeTools) return tools;

    // Caller passed a wide tool list — narrow to the top common ones so we
    // do not blow the KV budget on schema overhead.
    final preferred = _androidGemma4PreferredToolNames;
    final narrowed = <Tool>[];
    final seenNames = <String>{};
    for (final tool in tools) {
      if (preferred.contains(tool.name) && !seenNames.contains(tool.name)) {
        narrowed.add(tool);
        seenNames.add(tool.name);
      }
      if (narrowed.length >= _androidGemma4MaxNativeTools) break;
    }

    return narrowed.isEmpty ? tools : narrowed;
  }

  static const _androidGemma4MaxNativeTools = 5;

  /// High-frequency on-device tool names that should be passed through the
  /// native schema on tight Android Gemma 4 sessions. Tools outside this set
  /// remain available via the text-JSON fallback in
  /// [_deviceToolsCapabilitySuffix].
  static const _androidGemma4PreferredToolNames = <String>{
    'get_time',
    'set_alarm',
    'cancel_alarm',
    'open_app',
    'open_settings',
    'search_web',
    'take_screenshot',
    'generate_image',
  };

  /// When Auto lands on SmolLM but the turn has tools and Gemma 3 fits free
  /// RAM, escalate so function calling actually works.
  Future<NovaModel> _maybeEscalateForTools({
    required NovaModel model,
    required List<Tool> tools,
  }) async {
    if (tools.isEmpty) return model;
    if (model.supportsFunctionCalling && model != NovaModel.smollm) {
      return model;
    }
    // Respect an explicit pin to SmolLM / non-FC model.
    if (_preferredModelOverride != null) return model;

    final block = await PlatformAdaptationService.instance.checkCanLoadModel(
      NovaModel.gemma3_1b,
    );
    if (block != null) return model;

    _statusController.add('Using Gemma 3 1B for tools');

    return NovaModel.gemma3_1b;
  }

  String _chatSessionKey({
    required NovaModel model,
    required List<Tool> chatTools,
    required bool hasRag,
    required bool hasAttachments,
  }) {
    final toolNames = chatTools.map((t) => t.name).join(',');

    return '${model.name}|$toolNames|rag=$hasRag|att=$hasAttachments';
  }

  /// Stops generation, closes the engine, and clears native identity.
  Future<void> resetInferenceSession() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _stopBatteryCheck();
    _previousModelBeforeBattery = null;
    await _tryStopGeneration();
    try {
      await _activeChat?.close();
    } catch (e) {
      debugPrint('resetInferenceSession: chat close failed: $e');
    }
    _activeChat = null;
    _lastChatSessionKey = null;
    _pendingReplay = const [];
    _lastReplaySource = const [];
    await _teardownPartialLoad();
    _isStreaming = false;
    _isLoadingModel = false;
    _pendingIdleRelease = false;
    _pendingModelTeardown = false;
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
    _streamingCompleter = null;
    _releaseInferenceLock();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('dev.nova.assistant/diagnostics');
        await channel.invokeMethod<void>('requestGc');
      } catch (e) {
        debugPrint('resetInferenceSession: GC hint failed: $e');
      }
    }
    _statusController.add('Inference engine reset');
  }

  /// Called from the stream `finally` block to finish deferred teardown.
  void _onStreamEnded() {
    if (_pendingModelTeardown) {
      _pendingModelTeardown = false;
      unawaited(_teardownActiveModel(keepIfSameType: _preferredModelOverride));
    }
    if (_pendingIdleRelease) {
      _pendingIdleRelease = false;
      unawaited(_releaseIdleResources());
    } else {
      _resetIdleTimer();
    }
  }

  Future<void> prefetchModels() async {
    _statusController.add('Checking models...');
    try {
      // NEVER download in prefetch — only register models already on disk.
      // Downloads happen lazily in _getOrCreateModel() when actually needed.
      await _registerInstalledModels();
      _statusController.add('Models ready');
    } catch (e) {
      _statusController.add('Model check failed: $e');
    }
  }

  /// Scan disk for model files and register them without downloading.
  Future<void> _registerInstalledModels() async {
    final dir = await getApplicationDocumentsDirectory();

    final modelsDir = Directory('${dir.path}/models');
    final fileIndex = <String, File>{};

    if (await modelsDir.exists()) {
      await for (final entity in modelsDir.list()) {
        if (entity is File) {
          final entityName = p.basename(entity.path);
          final baseName = entityName
              .replaceAll('.litertlm', '')
              .replaceAll('.task', '');
          fileIndex[baseName] = entity;
        }
      }
    }

    for (final model in NovaModel.values) {
      final fileName = ModelHuggingFaceURLs.fileNameFor(model);

      File? foundFile;
      final directFile = File('${dir.path}/$fileName');
      if (await directFile.exists()) {
        foundFile = directFile;
      } else {
        final baseName = fileName
            .replaceAll('.litertlm', '')
            .replaceAll('.task', '');
        foundFile = fileIndex[baseName];
      }

      if (foundFile != null) {
        if (ModelManager.instance.isModelInstalled(fileName)) {
          try {
            final fileSize = await foundFile.length();
            if (fileSize == 0) {
              throw Exception('Model file is empty');
            }
            _statusController.add('Model ${model.displayName} verified');
            ModelManager.instance.cacheModelPath(fileName, foundFile.path);
          } catch (e) {
            debugPrint('Model health check failed for $fileName: $e');
            await ModelManager.instance.uninstallModel(fileName);
            try {
              await foundFile.delete();
              _statusController.add('Removed corrupt model: $fileName');
            } catch (e) {
              debugPrint(
                'ModelOrchestrator: failed to delete corrupt model file: $e',
              );
            }
          }
        } else {
          await ModelManager.instance.registerDiskModel(
            filePath: foundFile.path,
            fileName: fileName,
            modelType: model.modelType,
            fileType: model.fileType,
            fileSizeBytes: await foundFile.length(),
            deferInstall: true,
          );
        }
      } else if (ModelManager.instance.isModelInstalled(fileName)) {
        debugPrint('Model file missing for $fileName, removing from installed');
        await ModelManager.instance.uninstallModel(fileName);
      }
    }
  }

  Future<InferenceModel> _getOrCreateModel(
    NovaModel model, [
    Uint8List? screenshot,
  ]) async {
    // Wait for any ongoing release to complete before loading new model
    if (_isReleasing) {
      debugPrint('Waiting for resource release to complete...');
      await _releaseCompleter?.future;
    }

    // Vision models must always load with vision enabled. Lazy enablement
    // (only when screenshot != null) left the engine at max_num_images:0;
    // flutter_gemma's singleton then ignored a later supportImage:true.
    final needsImageSupport = model.hasVision;

    // Return cached model if same type, image support, AND token limit match
    if (_activeModel != null &&
        _activeModelType == model &&
        _activeModelSupportsImage == needsImageSupport) {
      final currentLimit = _tokenLimitFor(model);
      if (_activeModelMaxTokens != null &&
          _activeModelMaxTokens != currentLimit) {
        // maxTokens changed (e.g. high-context toggle) — force reload
        debugPrint(
          'maxTokens changed $_activeModelMaxTokens→$currentLimit, reloading...',
        );
        try {
          await _activeModel!.close();
        } catch (_) {}
        _activeModel = null;
        _activeModelType = null;
        _activeModelSupportsImage = false;
        _activeModelMaxTokens = null;
      } else {
        return _activeModel!;
      }
    }

    // Free-RAM hard gate before a cold load of heavy models (Android).
    // If blocked, auto-fallback to a smaller installed-capable model instead of
    // failing the whole turn (POCO F1 / ~1.2GB free cannot load Gemma 4).
    var modelToLoad = model;
    var ramBlock = await PlatformAdaptationService.instance.checkCanLoadModel(
      modelToLoad,
    );
    // #region agent log
    _debugLog(
      hypothesisId: 'C',
      location: 'model_orchestrator.dart:_getOrCreateModel:ramGate',
      message: 'RAM gate decision',
      data: {
        'requested': model.displayName,
        'blocked': ramBlock != null,
        'blockMsg': ramBlock,
        'availMemMb': MemoryDiagnosticsService.instance.lastAvailMemMb,
      },
    );
    // #endregion
    if (ramBlock != null) {
      final pinned =
          _preferredModelOverride != null ||
          _preferredCustomModelOverride != null;
      if (pinned) {
        throw ModelException(
          ramBlock,
          model: modelToLoad,
          suggestion: modelToLoad.sizeMB >= 2000
              ? 'Your selected model is pinned. Free RAM, switch to Gemma 3 1B '
                    'in the model picker, or use Settings → Reset inference. '
                    'Nova will not silently switch to SmolLM.'
              : 'Your selected model is pinned for this session. Free RAM, '
                    'use Settings → Reset inference, or pick a smaller model — '
                    'Nova will not silently switch to SmolLM.',
        );
      }
      final fallback = await _pickRamFallback(modelToLoad);
      if (fallback != null) {
        // #region agent log
        _debugLog(
          hypothesisId: 'C',
          location: 'model_orchestrator.dart:_getOrCreateModel:fallback',
          message: 'RAM gate fallback',
          data: {
            'from': modelToLoad.displayName,
            'to': fallback.displayName,
            'fileName': ModelHuggingFaceURLs.fileNameFor(fallback),
            'onDisk': await ModelManager.instance.isInstalledOnDisk(
              ModelHuggingFaceURLs.fileNameFor(fallback),
            ),
          },
        );
        // #endregion
        _statusController.add(
          'Low free RAM — using ${fallback.displayName} instead of '
          '${modelToLoad.displayName}',
        );
        modelToLoad = fallback;
        ramBlock = null;
      }
    }
    if (ramBlock != null) {
      throw ModelException(
        ramBlock,
        model: modelToLoad,
        suggestion:
            'Free RAM by closing apps, or use a smaller model in Settings.',
      );
    }

    // --- Switching / Loading new model ---
    // Close any previous model and clear flutter_gemma's active identity.
    // Always clear when vision flag or model type changes — singleton reuse
    // otherwise keeps a non-vision engine.
    if (_activeModel != null) {
      try {
        await _activeModel!.close();
      } catch (e) {
        debugPrint('Error closing previous model: $e');
      }
      _activeModel = null;
      _activeChat = null;
    }

    // Clear flutter_gemma's internal state whenever we need a fresh engine
    // (different model OR vision support mismatch).
    if (FlutterGemma.hasActiveModel()) {
      try {
        await FlutterGemma.clearActiveInferenceIdentity();
      } catch (e) {
        debugPrint('Error clearing active identity: $e');
      }
    }

    final bool supportImage = modelToLoad.hasVision;

    _isLoadingModel = true;
    _statusController.add(
      supportImage && modelToLoad == NovaModel.gemma4E2b
          ? 'Compiling ${modelToLoad.displayName} on GPU (vision enabled; first load may take 1–2 min)...'
          : 'Loading ${modelToLoad.displayName}...',
    );

    try {
      // First, ensure the model is registered with flutter_gemma
      final fileName = ModelHuggingFaceURLs.fileNameFor(modelToLoad);
      final existsOnDisk = await ModelManager.instance.isInstalledOnDisk(
        fileName,
      );
      final prefsInstalled = ModelManager.instance.isModelInstalled(fileName);

      // #region agent log
      _debugLog(
        hypothesisId: 'H2-H4',
        location: 'model_orchestrator.dart:_getOrCreateModel:check',
        message: 'Model availability check before load',
        data: {
          'model': modelToLoad.name,
          'fileName': fileName,
          'existsOnDisk': existsOnDisk,
          'prefsInstalled': prefsInstalled,
        },
      );
      // #endregion

      if (existsOnDisk) {
        _statusController.add(
          'Found ${modelToLoad.displayName} on disk, registering...',
        );
        try {
          final modelPath = await _findModelPath(fileName);
          if (modelPath != null) {
            final fileSize = await File(modelPath).length();
            // Always call registerDiskModel to ensure model is properly registered
            await ModelManager.instance.registerDiskModel(
              filePath: modelPath,
              fileName: fileName,
              modelType: modelToLoad.modelType,
              fileType: modelToLoad.fileType,
              fileSizeBytes: fileSize,
            );

            // Now get the active model
            _statusController.add('Loading ${modelToLoad.displayName}...');
            if (_debugMode) {
              unawaited(
                MemoryDiagnosticsService.instance.readProcessMemoryMb(),
              );
            }
            await MemoryDiagnosticsService.instance.readTotalMemMb();
            final backend = PlatformAdaptationService.instance
                .preferredBackendFor(modelToLoad);
            // #region agent log
            unawaited(
              AgentDebugLog.log(
                hypothesisId: 'F',
                location: 'model_orchestrator.dart:_getOrCreateModel:backend',
                message: 'Preferred backend for load',
                data: {
                  'model': modelToLoad.name,
                  'backend': backend.name,
                  'totalMemMb':
                      MemoryDiagnosticsService.instance.lastTotalMemMb,
                },
                runId: 'post-fix',
              ),
            );
            // #endregion
            _activeModel = await _loadActiveModelWithTimeout(
              modelToLoad: modelToLoad,
              supportImage: supportImage,
              preferredBackend: backend,
            );
            _activeModelType = modelToLoad;
            _activeModelSupportsImage = supportImage;
            _activeModelMaxTokens = _tokenLimitFor(modelToLoad);
            _isInitialized = true;
            _isLoadingModel = false;
            _statusController.add('${modelToLoad.displayName} ready');
            _startModelKeepAlive(modelToLoad.displayName);
            _resetIdleTimer();
            return _activeModel!;
          }
        } on TimeoutException catch (e) {
          debugPrint('Failed to load local model: $e');
          await _teardownPartialLoad();
          throw ModelLoadException(
            '${modelToLoad.displayName} is still loading.',
            model: modelToLoad,
            suggestion:
                'First boot compile can take 1–2 minutes. Wait and try again, '
                'or use Settings → Debug → Reset inference engine.',
            underlyingError: e,
          );
        } catch (e) {
          debugPrint('Failed to load local model: $e');
          // File exists but failed to load — likely corrupted or incompatible.
          // Convert to a typed exception so the UI can show actionable info.
          if (e is ModelException) rethrow;
          if (e is TimeoutException) {
            await _teardownPartialLoad();
            throw ModelLoadException(
              '${modelToLoad.displayName} is still loading.',
              model: modelToLoad,
              suggestion: 'First boot GPU compile can take 1–2 minutes. Wait and try again.',
              underlyingError: e,
            );
          }
          await _teardownPartialLoad();
          throw ModelLoadException(
            'Failed to load ${modelToLoad.displayName} from disk.',
            model: modelToLoad,
            suggestion:
                'The model file may be corrupted. '
                'Try re-downloading, reset inference in Settings, or pick a different file.',
            underlyingError: e,
          );
        }
      }

      // No active model or load failed — ask user before downloading
      final url = ModelHuggingFaceURLs.urlFor(modelToLoad);
      final choice = await _showDownloadConsent(model: modelToLoad, url: url);

      if (choice == DownloadConsent.pickFile) {
        // User wants to pick a file from device — throw a special exception
        // so the UI can handle the file picker flow.
        throw ModelNeedsFilePickException(modelToLoad);
      }

      if (choice == DownloadConsent.cancel) {
        throw Exception('Download cancelled by user');
      }

      // choice == DownloadConsent.download — proceed with network install
      _statusController.add('Downloading ${modelToLoad.displayName}...');
      try {
        final installed = await ModelManager.instance
            .installFromNetwork(
              url: url,
              modelType: modelToLoad.modelType,
              fileType: modelToLoad.fileType,
              onProgress: (progress) {
                _statusController.add(
                  'Downloading ${modelToLoad.displayName}: $progress%',
                );
              },
            )
            // Gemma 4 ~2.5GB needs far more than 5 minutes even on fast WiFi.
            .timeout(const Duration(minutes: 45));

        if (installed == null) {
          throw ModelDownloadException(
            'Download of ${modelToLoad.displayName} failed.',
            model: modelToLoad,
            suggestion: 'Check your internet connection and try again.',
          );
        }

        // Now get the model after install
        _statusController.add('Loading ${modelToLoad.displayName}...');
        await MemoryDiagnosticsService.instance.readTotalMemMb();
        final backend = PlatformAdaptationService.instance.preferredBackendFor(
          modelToLoad,
        );
        _activeModel = await _loadActiveModelWithTimeout(
          modelToLoad: modelToLoad,
          supportImage: supportImage,
          preferredBackend: backend,
        );
        _activeModelType = modelToLoad;
        _activeModelSupportsImage = supportImage;
        _isInitialized = true;
        _isLoadingModel = false;
        _statusController.add('${modelToLoad.displayName} ready');
        _resetIdleTimer();
        return _activeModel!;
      } on ModelException {
        rethrow;
      } on TimeoutException catch (e) {
        await _teardownPartialLoad();
        throw ModelLoadException(
          '${modelToLoad.displayName} is still loading.',
          model: modelToLoad,
          suggestion:
              'First boot compile can take 1–2 minutes. Wait and try again, '
              'or use Settings → Debug → Reset inference engine.',
          underlyingError: e,
        );
      } catch (e) {
        _statusController.add('Failed to load ${modelToLoad.displayName}: $e');
        // Classify the error
        final msg = e.toString().toLowerCase();
        if (msg.contains('storage') || msg.contains('no space')) {
          throw ModelStorageException(
            'Not enough storage for ${modelToLoad.displayName}.',
            model: modelToLoad,
            suggestion: 'Free up storage space and try again.',
            underlyingError: e,
          );
        }
        if (msg.contains('corrupt') ||
            msg.contains('invalid') ||
            msg.contains('unsupported')) {
          throw ModelLoadException(
            '${modelToLoad.displayName} file is corrupted or incompatible.',
            model: modelToLoad,
            suggestion: 'Re-download the model or pick a different file.',
            underlyingError: e,
          );
        }
        if (msg.contains('network') ||
            msg.contains('connection') ||
            msg.contains('socket')) {
          throw ModelDownloadException(
            'Network error downloading ${modelToLoad.displayName}.',
            model: modelToLoad,
            suggestion: 'Check your internet connection and try again.',
            underlyingError: e,
          );
        }
        throw ModelLoadException(
          'Failed to load ${modelToLoad.displayName}.',
          model: modelToLoad,
          suggestion: 'Try again or pick a file from your device.',
          underlyingError: e,
        );
      }
    } finally {
      _isLoadingModel = false;
    }
  }

  /// Pick a smaller model that fits free RAM.
  ///
  /// Prefers Gemma 3 1B when it fits (better quality / tools), then SmolLM.
  /// Prefers models already on disk (no download) within that order.
  Future<NovaModel?> _pickRamFallback(NovaModel blocked) async {
    const candidates = <NovaModel>[NovaModel.gemma3_1b, NovaModel.smollm];
    NovaModel? firstDownloadable;

    for (final candidate in candidates) {
      if (candidate == blocked) continue;
      final block = await PlatformAdaptationService.instance.checkCanLoadModel(
        candidate,
      );
      if (block != null) continue;

      final fileName = ModelHuggingFaceURLs.fileNameFor(candidate);
      final onDisk = await ModelManager.instance.isInstalledOnDisk(fileName);
      if (onDisk) {
        return candidate;
      }
      firstDownloadable ??= candidate;
    }

    return firstDownloadable;
  }

  /// Apply Auto-mode defaults for low free-RAM devices (call at startup).
  Future<void> applyRamAwareModelDefaults() async {
    if (_preferredModelOverride != null &&
        _preferredCustomModelOverride == null) {
      final block = await PlatformAdaptationService.instance.checkCanLoadModel(
        _preferredModelOverride!,
      );
      if (block != null) {
        _preferredModelOverride = null;
        _modelOverrideDirty = false;
        unawaited(_persistPreferredModel(null));
      }
    }

    if (_preferredCustomModelOverride != null) {
      final custom = _preferredCustomModelOverride!;
      final availMemMb = await MemoryDiagnosticsService.instance
          .readAvailableMemMb();
      final modelSizeMb = custom.fileSizeMB;
      if (availMemMb != null && modelSizeMb > 0) {
        final minFree = modelSizeMb >= 2000
            ? 1800
            : modelSizeMb >= 400
            ? 700
            : null;
        if (minFree != null && availMemMb < minFree) {
          _preferredCustomModelOverride = null;
          _modelOverrideDirty = false;
          unawaited(_persistPreferredCustomModel(null));
        }
      }
    }

    final recommended = await PlatformAdaptationService.instance
        .recommendModelForDevice();
    if (selector.primaryHeavy != recommended) {
      selector.primaryHeavy = recommended;
      // #region agent log
      _debugLog(
        hypothesisId: 'E',
        location: 'model_orchestrator.dart:applyRamAwareModelDefaults',
        message: 'Adjusted Auto primaryHeavy for free RAM',
        data: {
          'primaryHeavy': recommended.displayName,
          'availMemMb': MemoryDiagnosticsService.instance.lastAvailMemMb,
        },
        runId: 'post-fix',
      );
      // #endregion
    }
  }

  /// Process a message using a custom (user-imported) model.
  Stream<InferenceResult> _processWithCustomModel({
    required String query,
    required Uint8List? screenshot,
    required bool thinkingMode,
    required List<Tool> tools,
    String? ragContext,
    String? attachmentContext,
    required bool hasImageAttachments,
    required bool hasExtraContext,
  }) async* {
    final customModel = _preferredCustomModelOverride!;
    _statusController.add('Using custom model: ${customModel.displayName}');

    final availMemMb = await MemoryDiagnosticsService.instance
        .readAvailableMemMb();
    final modelSizeMb = customModel.fileSizeMB;
    if (availMemMb != null && modelSizeMb > 0) {
      final minFree = modelSizeMb >= 2000
          ? 1800
          : modelSizeMb >= 400
          ? 700
          : null;
      if (minFree != null && availMemMb < minFree) {
        yield InferenceResult(
          text:
              'Not enough free RAM to load ${customModel.displayName} '
              '($availMemMb MB free, need ~$minFree MB free). '
              'Close background apps or switch to a smaller model.',
          model: selector.primaryHeavy,
          isStreaming: false,
        );
        return;
      }
    }

    // Check if this is a GGUF model - route to GgufService
    if (customModel.isGguf) {
      yield* _processGgufModel(
        query: query,
        screenshot: screenshot,
        thinkingMode: thinkingMode,
        tools: tools,
        ragContext: ragContext,
        attachmentContext: attachmentContext,
        hasImageAttachments: hasImageAttachments,
      );
      return;
    }

    // Find the custom model file on disk
    final dir = await getApplicationDocumentsDirectory();
    String? modelPath;

    // Check direct path
    final directFile = File('${dir.path}/${customModel.fileName}');
    if (await directFile.exists()) {
      modelPath = directFile.path;
    } else {
      // Check models subdirectory
      final modelsDir = Directory('${dir.path}/models');
      if (await modelsDir.exists()) {
        final baseName = customModel.fileName
            .replaceAll('.litertlm', '')
            .replaceAll('.task', '')
            .replaceAll('.gguf', '');
        await for (final entity in modelsDir.list()) {
          if (entity is File) {
            final entityName = p.basename(entity.path);
            final entityBaseName = entityName
                .replaceAll('.litertlm', '')
                .replaceAll('.task', '')
                .replaceAll('.gguf', '');
            if (entityBaseName.contains(baseName) ||
                baseName.contains(entityBaseName)) {
              modelPath = entity.path;
              break;
            }
          }
        }
      }
    }

    if (modelPath == null) {
      _statusController.add(
        'Custom model file not found: ${customModel.fileName}',
      );
      yield InferenceResult(
        text:
            'Custom model file not found: ${customModel.fileName}\n\n'
            'The model may have been deleted. Try re-importing it.',
        model: selector.primaryHeavy,
        isStreaming: false,
      );
      return;
    }

    // Register and load the custom model
    InferenceModel inferenceModel;
    try {
      final fileSize = await File(modelPath).length();
      final needsImageSupport = customModel.hasVision;

      // Clear BEFORE register — clearing after install() leaves no active model.
      await _teardownActiveModel();
      if (FlutterGemma.hasActiveModel()) {
        try {
          await FlutterGemma.clearActiveInferenceIdentity();
        } catch (_) {}
      }

      await ModelManager.instance.registerDiskModel(
        filePath: modelPath,
        fileName: customModel.fileName,
        modelType: customModel.modelType,
        fileType: customModel.fileType,
        fileSizeBytes: fileSize,
      );

      _statusController.add('Loading ${customModel.displayName}...');
      await MemoryDiagnosticsService.instance.readTotalMemMb();
      final total = MemoryDiagnosticsService.instance.lastTotalMemMb;
      final backend = (total != null && total < 6656)
          ? PreferredBackend.cpu
          : PreferredBackend.gpu;
      // #region agent log
      _debugLog(
        hypothesisId: 'F',
        location: 'model_orchestrator.dart:_processWithCustomModel:load',
        message: 'Loading custom model after register',
        data: {
          'fileName': customModel.fileName,
          'backend': backend.name,
          'totalMemMb': total,
          'hasActive': FlutterGemma.hasActiveModel(),
        },
        runId: 'post-fix',
      );
      // #endregion
      inferenceModel = await _loadActiveModelWithTimeout(
        maxTokens: MessageLimits.clampCustomContextTokens(
          customModel.maxContextTokens,
        ),
        timeout: const Duration(seconds: 120),
        supportImage: needsImageSupport,
        preferredBackend: backend,
      );

      // Track so idle release / model switch can unload it
      _activeModel = inferenceModel;
      _activeModelType = null;
      _activeModelSupportsImage = needsImageSupport;
      _isInitialized = true;
      _resetIdleTimer();

      _statusController.add('${customModel.displayName} ready');
    } on TimeoutException {
      await _teardownPartialLoad();
      yield InferenceResult(
        text:
            'Timed out loading ${customModel.displayName}. '
            'The model may be too large for your device.',
        model: selector.primaryHeavy,
        isStreaming: false,
      );
      return;
    } catch (e) {
      _statusController.add('Error loading custom model: $e');
      yield InferenceResult(
        text: 'Failed to load ${customModel.displayName}: $e',
        model: selector.primaryHeavy,
        isStreaming: false,
      );
      return;
    }

    // Create chat with system prompt (include adult/local-first lead).
    final buffer = StringBuffer();
    if (_adultModeEnabled) {
      buffer.write(AdultModePolicy.systemPromptLead(compact: false));
    }
    buffer.write(_getAssistantRole().systemPrompt);

    if (customModel.hasThinking) {
      buffer.write(
        ' When asked to think step by step, show your reasoning in <thinking> tags '
        'before your final answer.',
      );
    }

    buffer.write('\n\n${await _languageInstruction()}');
    if (_adultModeEnabled) {
      buffer.write(AdultModePolicy.systemPromptSuffix(compact: false));
    }

    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.write('\n\n${_capContextInjection(ragContext)}');
    }
    if (attachmentContext != null && attachmentContext.isNotEmpty) {
      buffer.write(
        '\n\n--- Attached Data ---\n${_capContextInjection(attachmentContext)}',
      );
    }

    final chat = await inferenceModel.createChat(
      systemInstruction: buffer.toString(),
      tools: tools,
      supportImage: customModel.hasVision && _activeModelSupportsImage,
    );

    final queryError = _validateQueryLength(
      query: query,
      isCustomModel: true,
      hasAttachments: hasExtraContext,
    );
    if (queryError != null) {
      _statusController.add('Message too long');
      yield InferenceResult(
        text: '⚠️ $queryError',
        model: selector.primaryHeavy,
        isStreaming: false,
      );

      return;
    }

    // Add the user message
    final Message message;
    if (screenshot != null &&
        screenshot.isNotEmpty &&
        _activeModelSupportsImage) {
      final visionBytes = await VisionImagePrep.prepareForInference(screenshot);
      message = Message.withImage(
        text: query,
        imageBytes: visionBytes,
        isUser: true,
      );
    } else {
      message = Message.text(text: query, isUser: true);
    }

    try {
      await chat.addQuery(message);
    } catch (e) {
      final err = e.toString();
      final isImageUnsupported = err.contains('does not support image input');
      yield InferenceResult(
        text: isImageUnsupported
            ? '⚠️ The current model can\'t process images. Switch to a '
                  'vision model (FastVLM or Gemma 4) in Settings, or send '
                  'text-only input.'
            : '⚠️ Could not start inference with this image.\n\n$e',
        model: selector.primaryHeavy,
        isStreaming: false,
      );

      return;
    }

    // Generate response
    String fullResponse = '';
    String? currentThinking;
    final textBuffer = StringBuffer();
    final inferenceStopwatch = Stopwatch()..start();

    bool hasPendingToolCalls = true;
    int toolRounds = 0;
    final List<Map<String, dynamic>> allToolCalls = [];
    final executedToolSignatures = <String>{};
    final lastToolResults = <String, Map<String, dynamic>>{};
    var safetyStopped = false;
    final maxOutputChars = GenerationSafety.maxOutputCharsForCustom();

    _isStreaming = true;
    _streamingCompleter = Completer<void>();
    try {
      while (hasPendingToolCalls && toolRounds < _maxToolRounds) {
        hasPendingToolCalls = false;
        toolRounds++;

        await for (final event in chat.generateChatResponseAsync()) {
          if (_streamingCompleter?.isCompleted ?? false) {
            debugPrint('Custom model stream aborted');
            break;
          }
          if (event is TextResponse) {
            final token = event.token;
            fullResponse += token;
            textBuffer.write(token);

            final safetyMsg = GenerationSafety.safetyStopMessage(
              fullResponse,
              maxOutputChars,
            );
            if (safetyMsg != null) {
              safetyStopped = true;
              fullResponse = '$fullResponse$safetyMsg';
              yield InferenceResult(
                text: _sanitizeAssistantText(fullResponse),
                model: selector.primaryHeavy,
                isStreaming: true,
                thinking: currentThinking,
                toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
                inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
              );
              unawaited(stopGeneration());
              break;
            }

            final parsedCalls = _tryParseFunctionCalls(textBuffer.toString());
            if (parsedCalls != null && parsedCalls.isNotEmpty) {
              fullResponse = _sanitizeAssistantText(fullResponse);
              textBuffer.clear();

              for (final parsed in parsedCalls) {
                final toolName = parsed['name'] as String;
                final toolArgs = Map<String, dynamic>.from(
                  parsed['args'] as Map,
                );
                final signature = ToolCallParser.callSignature(
                  toolName,
                  toolArgs,
                );
                if (executedToolSignatures.contains(signature)) {
                  allToolCalls.add({
                    'name': toolName,
                    'args': toolArgs,
                    'result': {
                      'success': true,
                      'message':
                          'Already called this turn with the same arguments. '
                          'Use the previous result. Do not call this tool again.',
                      if (lastToolResults[signature] != null)
                        'previous': lastToolResults[signature],
                    },
                    'status': 'completed',
                  });
                  hasPendingToolCalls = false;
                  continue;
                }

                _statusController.add('Executing $toolName...');

                allToolCalls.add({
                  'name': toolName,
                  'args': toolArgs,
                  'status': 'executing',
                });

                ExternalToolResult? mcpResult;
                if (McpService.instance.getTool(toolName) != null) {
                  mcpResult = await McpService.instance.executeTool(
                    toolName,
                    toolArgs,
                  );
                }

                final Map<String, dynamic> toolResult;
                if (mcpResult != null) {
                  toolResult = mcpResult.toJson();
                } else {
                  toolResult = await ToolExecutorService.instance.executeTool(
                    toolName,
                    toolArgs,
                  );
                }

                executedToolSignatures.add(signature);
                lastToolResults[signature] = toolResult;

                allToolCalls.add({
                  'name': toolName,
                  'args': toolArgs,
                  'result': toolResult,
                  'status': 'completed',
                });

                hasPendingToolCalls = true;
              }
            }

            yield InferenceResult(
              text: _sanitizeAssistantText(fullResponse),
              model: selector.primaryHeavy,
              isStreaming: true,
              thinking: currentThinking,
              toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
              inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
            );
          } else if (event is ThinkingResponse) {
            currentThinking = event.content;
            yield InferenceResult(
              text: _sanitizeAssistantText(fullResponse),
              model: selector.primaryHeavy,
              isStreaming: true,
              thinking: currentThinking,
              toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
              inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
            );
          }
        }

        if (safetyStopped || (_streamingCompleter?.isCompleted ?? false)) {
          break;
        }

        if (hasPendingToolCalls) {
          final toolResultMessages = <Message>[];
          for (final tc in allToolCalls.where(
            (t) => t['status'] == 'completed' && t['result'] != null,
          )) {
            toolResultMessages.add(
              Message.text(text: jsonEncode(tc['result']), isUser: true),
            );
          }
          if (toolResultMessages.isNotEmpty) {
            for (final msg in toolResultMessages) {
              await chat.addQuery(msg);
            }
          }
        }
      }
    } finally {
      _isStreaming = false;
      if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
        _streamingCompleter!.complete();
      }
      _streamingCompleter = null;
      _onStreamEnded();
    }

    inferenceStopwatch.stop();
    fullResponse = _sanitizeAssistantText(fullResponse);

    yield InferenceResult(
      text: fullResponse,
      model: selector.primaryHeavy,
      isStreaming: false,
      thinking: currentThinking,
      toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
      inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
    );
  }

  /// Process a message using a GGUF model via GgufService.
  Stream<InferenceResult> _processGgufModel({
    required String query,
    required Uint8List? screenshot,
    required bool thinkingMode,
    required List<Tool> tools,
    String? ragContext,
    String? attachmentContext,
    required bool hasImageAttachments,
  }) async* {
    // GGUF support requires llamadart package, which currently conflicts with
    // flutter_gemma_litertlm native libraries. Show a clear error message.
    yield InferenceResult(
      text:
          'GGUF models are not supported for inference.\n\n'
          'Please use a .litertlm or .task model instead.',
      model: selector.primaryHeavy,
      isStreaming: false,
    );
  }

  /// Show a download consent dialog before downloading a model.
  /// Returns the user's choice.
  Future<DownloadConsent> _showDownloadConsent({
    required NovaModel model,
    required String url,
  }) async {
    final completer = Completer<DownloadConsent>();
    _downloadConsentCompleter = completer;
    _downloadConsentModel = model;
    _downloadConsentUrl = url;
    _statusController.add('NEED_DOWNLOAD_CONSENT:${model.displayName}');
    return completer.future;
  }

  /// Completes the download consent dialog (called from UI layer).
  void completeDownloadConsent(DownloadConsent choice) {
    _downloadConsentCompleter?.complete(choice);
    _downloadConsentCompleter = null;
    _downloadConsentModel = null;
    _downloadConsentUrl = null;
  }

  Completer<DownloadConsent>? _downloadConsentCompleter;
  NovaModel? _downloadConsentModel;
  String? _downloadConsentUrl;

  NovaModel? get downloadConsentModel => _downloadConsentModel;
  String? get downloadConsentUrl => _downloadConsentUrl;

  int _tokenLimitFor(NovaModel model) {
    return MessageLimits.kvTokenLimitFor(
      model,
      highContext: _highContextEnabled,
    );
  }

  static const _contextBudgetRatio = 0.6;
  static const _maxContextInjectionChars = 3000;

  String _capContextInjection(String context) {
    if (context.length <= _maxContextInjectionChars) return context;

    return '${context.substring(0, _maxContextInjectionChars)}…\n'
        '[truncated for context budget]';
  }

  String? _validateQueryLength({
    required String query,
    NovaModel? model,
    bool isCustomModel = false,
    bool hasAttachments = false,
    bool hasVisionImage = false,
    int historyTokenEstimate = 0,
    int ragTokenEstimate = 0,
    int systemPromptTokenEstimate = 0,
  }) {
    if (model == null || isCustomModel) {
      return MessageLimits.validateLength(
        text: query,
        model: model,
        isCustomModel: isCustomModel,
        hasAttachments: hasAttachments,
      );
    }

    return MessageLimits.validateTokenBudget(
      text: query,
      effectiveModel: model,
      historyTokenEstimate: historyTokenEstimate,
      ragTokenEstimate: ragTokenEstimate,
      systemPromptTokenEstimate: systemPromptTokenEstimate,
      hasAttachments: hasAttachments,
      hasVisionImage: hasVisionImage,
      highContext: _highContextEnabled,
    );
  }

  Future<void> _truncateContext(InferenceChat chat, NovaModel model) async {
    final limit = _tokenLimitFor(model);
    final budget = (limit * _contextBudgetRatio).round();
    final history = chat.fullHistory;

    int estimatedTokens = 0;
    for (final msg in history) {
      estimatedTokens += _estimateTokens(msg);
      if (estimatedTokens > budget) break;
    }

    if (estimatedTokens <= budget) return;

    final List<Message> keepMessages = [];
    for (final msg in history) {
      keepMessages.add(msg);
    }

    while (keepMessages.length > 2) {
      int recentLimit = (budget * 0.7).round();
      int tokenSum = 0;
      int cutoffIndex = keepMessages.length;

      for (var i = keepMessages.length - 1; i >= 0; i--) {
        tokenSum += _estimateTokens(keepMessages[i]);
        if (tokenSum > recentLimit) {
          cutoffIndex = i;
          break;
        }
      }

      if (cutoffIndex == 0 || cutoffIndex == keepMessages.length) break;

      final removed = cutoffIndex;
      keepMessages.removeRange(0, cutoffIndex);
      try {
        await chat.clearHistory(replayHistory: keepMessages);
        debugPrint(
          'Context truncated: removed $removed oldest messages, kept ${keepMessages.length}',
        );
        return;
      } on Exception catch (e) {
        debugPrint('Context truncation failed: $e');
        return;
      }
    }
  }

  int _estimateTokens(Message message) {
    if (message.hasImage) return MessageLimits.visionImageTokenEstimate;

    return (message.text.length / 4).round();
  }

  /// Real-token estimate for a chat message — uses the per-model tokenizer
  /// ratio table in [MessageLimits] instead of the legacy chars/4 heuristic.
  /// Falls back to the legacy estimate when no model is available.
  int _estimateRealTokens(Message message, [NovaModel? model]) {
    if (message.hasImage) return MessageLimits.visionImageTokenEstimate;

    return MessageLimits.estimateRealTokens(message.text, model: model);
  }

  NovaModel _selectModel({
    required String query,
    Uint8List? screenshot,
    bool hasImageAttachments = false,
    bool thinkingMode = false,
  }) {
    final hasVisionContext = screenshot != null || hasImageAttachments;

    if (_debugMode) {
      debugPrint(
        '[DEBUG] _selectModel called: '
        'query="${query.length > 50 ? "${query.substring(0, 50)}..." : query}", '
        'hasScreenshot=${screenshot != null}, '
        'hasImageAttachments=$hasImageAttachments, '
        'thinkingMode=$thinkingMode, '
        'primaryHeavy=${selector.primaryHeavy.displayName}, '
        'fastModel=${selector.fastModel.displayName}',
      );
    }

    // Stay on the loaded model when keep-warm is on and the model can handle
    // the query. This avoids query-length-based switching (A2) and prevents
    // vision/text model reloads (A1).
    if (_activeModel != null && _keepModelWarm && _activeModelType != null) {
      final current = _activeModelType!;
      if (hasVisionContext && !current.hasVision) {
        if (_debugMode) {
          debugPrint(
            '[DEBUG] _selectModel vision fallback from ${current.displayName}',
          );
        }
        if (selector.primaryHeavy.hasVision) return selector.primaryHeavy;
        if (selector.fastModel.hasVision) return selector.fastModel;
        return NovaModel.fastvlm;
      }
      if (thinkingMode && !current.hasThinking) {
        if (selector.primaryHeavy.hasThinking) return selector.primaryHeavy;
      }
      if (_debugMode) {
        debugPrint(
          '[DEBUG] _selectModel staying on ${current.displayName} '
          '(keep-warm, loaded model)',
        );
      }
      return current;
    }

    final selected = selector.selectForQuery(
      query: query,
      hasVisionContext: hasVisionContext,
      requestedThinking: thinkingMode,
    );

    if (_debugMode) {
      debugPrint(
        '[DEBUG] _selectModel selected: ${selected.displayName} '
        '(hasVision=${selected.hasVision})',
      );
    }

    if (hasVisionContext && !selected.hasVision) {
      if (selector.primaryHeavy.hasVision) return selector.primaryHeavy;
      if (selector.fastModel.hasVision) return selector.fastModel;
      return NovaModel.fastvlm;
    }

    return selected;
  }

  /// First installed vision-capable catalog model, or null.
  Future<NovaModel?> _installedVisionModel() async {
    for (final candidate in const [NovaModel.fastvlm, NovaModel.gemma4E2b]) {
      final fileName = ModelHuggingFaceURLs.fileNameFor(candidate);
      if (await ModelManager.instance.isInstalledOnDisk(fileName)) {
        return candidate;
      }
    }

    return null;
  }

  static const _maxToolRounds = 5;

  Stream<InferenceResult> processMessage({
    required String query,
    Uint8List? screenshot,
    bool thinkingMode = false,
    List<Tool> tools = const [],
    List<AttachedData> attachments = const [],

    /// When true, forces use of the primary heavy model instead of auto-selection.
    /// Useful for assistant mode where reliability is more important than speed.
    bool forcePrimaryModel = false,
  }) async* {
    if (_inferenceLock != null) {
      yield InferenceResult(
        text:
            '⚠️ Wait for the current response to finish before sending again.',
        model: selector.primaryHeavy,
        isStreaming: false,
      );

      return;
    }

    await _acquireInferenceLock();
    _generationCancelledByUser = false;

    try {
      // Deterministic timer shortcut (relative duration → wall-clock alarm).
      final parsedTimer = AlarmTimeParser.tryParseTimer(query);
      if (parsedTimer != null) {
        _statusController.add('Setting timer...');
        final message = 'Timer ${parsedTimer.durationMinutes} min';
        final result = await ToolExecutorService.instance.setAlarm(
          parsedTimer.hour,
          parsedTimer.minute,
          message,
        );
        final ok = result['success'] == true;
        final label =
            '${parsedTimer.hour.toString().padLeft(2, '0')}:'
            '${parsedTimer.minute.toString().padLeft(2, '0')}';
        yield InferenceResult(
          text: ok
              ? 'Timer set for ${parsedTimer.durationMinutes} minutes '
                    '(alarm at $label).'
              : 'Could not set the timer: ${result['error'] ?? 'unknown error'}',
          model: selector.primaryHeavy,
          isStreaming: false,
          toolCalls: [
            {
              'name': 'set_alarm',
              'args': {
                'hour': parsedTimer.hour,
                'minute': parsedTimer.minute,
                'message': message,
                'duration_minutes': parsedTimer.durationMinutes,
              },
              'result': result,
            },
          ],
        );
        return;
      }

      // Deterministic alarm shortcut: parse clock times and call set_alarm
      // without relying on the on-device model to convert AM/PM.
      final parsedAlarm = AlarmTimeParser.tryParse(query);
      if (parsedAlarm != null) {
        _statusController.add('Setting alarm...');
        final result = await ToolExecutorService.instance.setAlarm(
          parsedAlarm.hour,
          parsedAlarm.minute,
          'Nova alarm',
        );
        final ok = result['success'] == true;
        final label =
            '${parsedAlarm.hour.toString().padLeft(2, '0')}:'
            '${parsedAlarm.minute.toString().padLeft(2, '0')}';
        yield InferenceResult(
          text: ok
              ? 'Alarm set for $label.'
              : 'Could not set the alarm: ${result['error'] ?? 'unknown error'}',
          model: selector.primaryHeavy,
          isStreaming: false,
          toolCalls: [
            {
              'name': 'set_alarm',
              'args': {
                'hour': parsedAlarm.hour,
                'minute': parsedAlarm.minute,
                'message': 'Nova alarm',
              },
              'result': result,
            },
          ],
        );
        return;
      }

      // Deterministic open-app shortcut (YouTube, Settings, browser, etc.).
      final openPackage = OpenAppIntentParser.tryParsePackage(query);
      if (openPackage != null) {
        _statusController.add('Opening app...');
        final result = await ToolExecutorService.instance.openApp(openPackage);
        final ok = result['success'] == true;
        yield InferenceResult(
          text: ok
              ? 'Opened $openPackage.'
              : 'Could not open the app: ${result['error'] ?? 'unknown error'}',
          model: selector.primaryHeavy,
          isStreaming: false,
          toolCalls: [
            {
              'name': 'open_app',
              'args': {'package': openPackage},
              'result': result,
            },
          ],
        );
        return;
      }

      // Deterministic web-search shortcut — avoids Gemma looping on old RAG
      // topics like Twitch when the user only asked to search.
      final searchTerm = SearchWebIntentParser.tryParse(query);
      if (searchTerm != null) {
        _statusController.add('Searching the web...');
        final result = await ToolExecutorService.instance.searchWeb(searchTerm);
        final ok = result['success'] == true;
        yield InferenceResult(
          text: ok
              ? 'Opened web search for "$searchTerm".'
              : 'Could not search: ${result['error'] ?? 'unknown error'}',
          model: selector.primaryHeavy,
          isStreaming: false,
          toolCalls: [
            {
              'name': 'search_web',
              'args': {'query': searchTerm},
              'result': result,
            },
          ],
        );
        return;
      }

      // Check if there are image attachments that need vision processing
      final hasImageAttachments = attachments.any((att) {
        if (att.type != AttachedDataType.file) return false;
        final name = att.name.toLowerCase();
        return name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.gif') ||
            name.endsWith('.webp');
      });

      // Build attachment context if any
      String attachmentContext = '';
      if (attachments.isNotEmpty) {
        final buffers = <String>[];
        for (final att in attachments) {
          buffers.add(await att.buildContextString());
        }
        attachmentContext = buffers.join('\n\n');
      }

      final ragContext = _capContextInjection(
        await MemoryService.retrieveContext(
              query,
              conversationSummary:
                  ConversationSummaryService.instance.activeSummary,
            ) ??
            '',
      );

      if (_inferenceBackend == InferenceBackend.remote) {
        yield* _processRemoteMessage(
          query: query,
          ragContext: ragContext,
          attachmentContext: _capContextInjection(attachmentContext),
          tools: tools,
        );

        return;
      }

      final hasExtraContext =
          attachments.isNotEmpty ||
          (screenshot != null && screenshot.isNotEmpty);
      NovaModel model;
      if (_debugMode) {
        _statusController.add(
          '[DEBUG] Model selection: overrideDirty=$_modelOverrideDirty, '
          'preferred=${_preferredModelOverride?.displayName ?? "null"}, '
          'screenshot=${screenshot != null}, '
          'hasImageAttachments=$hasImageAttachments, thinking=$thinkingMode, '
          'forcePrimaryModel=$forcePrimaryModel',
        );
      }

      // Catalog preferred / custom pin wins over Auto forcePrimary so a user
      // who selected Gemma 3 is not silently forced onto primaryHeavy (SmolLM).
      if (_preferredCustomModelOverride != null) {
        // Custom model selected - use it directly (bypasses NovaModel selection)
        // Return early with custom model loading path
        yield* _processWithCustomModel(
          query: query,
          screenshot: screenshot,
          thinkingMode: thinkingMode,
          tools: tools,
          ragContext: ragContext,
          attachmentContext: _capContextInjection(attachmentContext),
          hasImageAttachments: hasImageAttachments,
          hasExtraContext: hasExtraContext,
        );
        return;
      } else if (_preferredModelOverride != null) {
        // Must match predictEffectiveModel: honor explicit selection even after
        // the first send clears _modelOverrideDirty. Otherwise Auto's
        // primaryHeavy (often SmolLM on ≤6GB) silently overrides Gemma 3.
        model = _preferredModelOverride!;
        if ((screenshot != null || hasImageAttachments) && !model.hasVision) {
          model = selector.primaryHeavy.hasVision
              ? selector.primaryHeavy
              : selector.fastModel;
          _statusController.add(
            'Auto-switched to ${model.displayName} for image input',
          );
        }
      } else if (forcePrimaryModel) {
        model = selector.primaryHeavy;
        if (_debugMode) {
          _statusController.add(
            '[DEBUG] Force Primary Model: ${model.displayName}',
          );
        }
      } else {
        model = _selectModel(
          query: query,
          screenshot: screenshot,
          hasImageAttachments: hasImageAttachments,
          thinkingMode: thinkingMode,
        );
      }

      var visionForced = false;
      final needsVision = screenshot != null || hasImageAttachments;
      if (needsVision && !model.hasVision) {
        final vision = await _installedVisionModel();
        if (vision != null) {
          model = vision;
          visionForced = true;
          _statusController.add(
            'Auto-switched to ${model.displayName} for image input',
          );
        } else {
          yield InferenceResult(
            text:
                '⚠️ This question needs a vision model (FastVLM or Gemma 4), '
                'but none is installed. Attach a screenshot and install a '
                'vision model in Settings, or ask a text-only question.',
            model: model,
            isStreaming: false,
          );

          return;
        }
      }
      // #region agent log
      _debugLog(
        hypothesisId: 'E',
        location: 'model_orchestrator.dart:processMessage:modelResolved',
        message: 'Resolved inference model for turn',
        data: {
          'model': model.name,
          'forcePrimary': forcePrimaryModel,
          'preferred': _preferredModelOverride?.name,
          'dirty': _modelOverrideDirty,
          'primaryHeavy': selector.primaryHeavy.name,
          'visionForced': visionForced,
          'needsVision': needsVision,
        },
        runId: 'post-fix',
      );
      // #endregion

      if (tools.isNotEmpty) {
        model = await _maybeEscalateForTools(model: model, tools: tools);
      }

      if (_debugMode) {
        _statusController.add(
          '[DEBUG] Selected model: ${model.displayName} '
          '(hasVision=${model.hasVision}, hasThinking=${model.hasThinking})',
        );
      }

      _statusController.add('Using ${model.displayName}');

      InferenceModel inferenceModel;
      try {
        inferenceModel = await _getOrCreateModel(model, screenshot);
      } on ModelNeedsFilePickException {
        rethrow; // Let the UI handle this
      } on ModelException catch (e) {
        _statusController.add('Error: ${e.message}');
        yield InferenceResult(
          text:
              '⚠️ ${e.message}\n\n${e.suggestion ?? 'Check Settings > AI Models.'}',
          model: model,
          isStreaming: false,
        );
        return;
      } catch (e) {
        _statusController.add('Error: $e');
        yield InferenceResult(
          text: 'Failed to load model: $e\n\nCheck Settings > AI Models.',
          model: model,
          isStreaming: false,
        );
        return;
      }

      // Auto RAM fallback may have loaded a different catalog model.
      if (_activeModelType != null && _activeModelType != model) {
        model = _activeModelType!;
        _statusController.add('Using ${model.displayName}');
      }

      if (_modelOverrideDirty) {
        _modelOverrideDirty = false;
      }

      // Vision + full native tool schemas + screenshot often exceeds KV
      // (e.g. 4609 >= 4096). Keep tools as text capability only on image turns.
      final visionInput = (screenshot != null && screenshot.isNotEmpty)
          ? screenshot
          : null;
      final hasVisionImage = visionInput != null && model.hasVision;
      final chatTools = hasVisionImage
          ? const <Tool>[]
          : _toolsForCreateChat(model, tools);
      // SmolLM has no FC and cannot absorb tool essays in a tiny KV window.
      final textToolPrompt =
          model != NovaModel.smollm && chatTools.isEmpty && tools.isNotEmpty;
      final systemInstruction = await _systemPromptFor(
        model,
        ragContext,
        _capContextInjection(attachmentContext),
        textToolPrompt ? tools : null,
      );
      final sessionKey = _chatSessionKey(
        model: model,
        chatTools: chatTools,
        hasRag: ragContext.trim().isNotEmpty,
        hasAttachments: hasExtraContext,
      );
      // Warm sessions ignore new systemInstruction / tools — recreate when
      // the fingerprint changes so RAG / adult / tools stay in sync.
      if (_activeChat != null &&
          _lastChatSessionKey != null &&
          _lastChatSessionKey != sessionKey) {
        _activeChat = null;
      }
      final wasNull = _activeChat == null;
      final pendingCount = _pendingReplay.length;
      // #region agent log
      _debugLog(
        hypothesisId: 'A',
        location: 'model_orchestrator.dart:processMessage:chatPrep',
        message: 'Chat session prep before create/replay',
        data: {
          'wasNull': wasNull,
          'pendingReplay': pendingCount,
          'model': model.name,
          'queryLen': query.length,
          'tools': tools.length,
          'chatTools': chatTools.length,
          'kvLimit': _tokenLimitFor(model),
          'systemPromptLen': systemInstruction.length,
          'textToolPrompt': textToolPrompt,
          'adultMode': _adultModeEnabled,
          'sessionKeyChanged': wasNull && _lastChatSessionKey != sessionKey,
          'computedOverhead': MessageLimits.computedOverheadFor(
            model,
            systemPromptChars: systemInstruction.length,
            toolsCount: chatTools.length,
            textToolPrompt: textToolPrompt,
            hasRag: ragContext.trim().isNotEmpty,
            hasAttachments: attachmentContext.trim().isNotEmpty,
          ),
        },
        runId: 'post-fix',
      );
      // #endregion
      if (wasNull) {
        _isLoadingModel = true;
        _statusController.add('Preparing chat session...');
      }
      try {
        _activeChat ??= await inferenceModel.createChat(
          systemInstruction: systemInstruction,
          tools: chatTools,
          supportImage: model.hasVision && _activeModelSupportsImage,
        );
        _lastChatSessionKey = sessionKey;
        if (wasNull && _pendingReplay.isNotEmpty) {
          final rawBudget = (_tokenLimitFor(model) * _contextBudgetRatio)
              .round();
          // Reserve the actual measured overhead for this turn (system prompt
          // length + jinja FC template + native tool schemas + RAG/attachment
          // wrappers) instead of the historical flat 220 token estimate.
          // Without this, replay budgets let the pre-call token count
          // overshoot the KV ceiling on Gemma 4 Android and produced
          // "Input token ids are too long" after just a handful of turns.
          final overhead = MessageLimits.computedOverheadFor(
            model,
            systemPromptChars: systemInstruction.length,
            toolsCount: chatTools.length,
            textToolPrompt: textToolPrompt,
            hasRag: ragContext.trim().isNotEmpty,
            hasAttachments: attachmentContext.trim().isNotEmpty,
          );
          final safetyMargin = MessageLimits.safetyMarginFor(model);
          final budget = (rawBudget - overhead - safetyMargin)
              .clamp(64, rawBudget)
              .toInt();
          final replay = SessionHistoryReinjection.buildReplayMessages(
            _pendingReplay,
            maxTokens: budget,
            model: model,
          );
          // Snapshot before consumption so the pre-flight auto-compact path
          // can fall back to a slimmed subset of the same turns when the
          // prompt is already over-budget.
          _lastReplaySource = List<ChatMessage>.from(_pendingReplay);
          _pendingReplay = const [];
          // #region agent log
          unawaited(
            AgentDebugLog.log(
              hypothesisId: 'A',
              location: 'model_orchestrator.dart:processMessage:reinject',
              message: 'Reinjecting history into new chat session',
              data: {
                'replayMessages': replay.length,
                'budget': budget,
                'rawBudget': rawBudget,
                'emptyTexts': replay.where((m) => m.text.trim().isEmpty).length,
              },
              runId: 'post-fix',
            ),
          );
          // #endregion
          if (replay.isNotEmpty) {
            try {
              await _activeChat!.clearHistory(replayHistory: replay);
            } on Exception catch (e) {
              debugPrint('History reinjection failed: $e');
              // Do not addQuery onto a half-broken session — recreate empty.
              _activeChat = null;
              _activeChat = await inferenceModel.createChat(
                systemInstruction: systemInstruction,
                tools: chatTools,
                supportImage: model.hasVision && _activeModelSupportsImage,
              );
              try {
                await _activeChat!.clearHistory(replayHistory: replay);
              } on Exception catch (e2) {
                debugPrint('History reinjection retry failed: $e2');
                _activeChat = null;
                await _teardownPartialLoad();
                yield InferenceResult(
                  text:
                      '⚠️ Could not restore chat history after edit. '
                      'Start a new conversation or try again.\n\n$e2',
                  model: model,
                  isStreaming: false,
                );

                return;
              }
            }
          }
        }
      } finally {
        if (_isLoadingModel) {
          _isLoadingModel = false;
        }
      }

      final ragTokenEstimate = MessageLimits.estimateRealTokens(
        ragContext,
        model: model,
      );
      final historyTokenEstimate = _activeChat!.fullHistory.fold<int>(
        0,
        (sum, msg) => sum + _estimateRealTokens(msg, model),
      );
      final systemPromptTokenEstimate = MessageLimits.estimateRealTokens(
        systemInstruction,
        model: model,
      );

      await _truncateContext(_activeChat!, model);

      final queryError = _validateQueryLength(
        query: query,
        model: model,
        hasAttachments: hasExtraContext,
        hasVisionImage: hasVisionImage,
        historyTokenEstimate: historyTokenEstimate,
        ragTokenEstimate: ragTokenEstimate,
        systemPromptTokenEstimate: systemPromptTokenEstimate,
      );
      if (queryError != null) {
        _statusController.add('Message too long');
        yield InferenceResult(
          text: '⚠️ $queryError',
          model: model,
          isStreaming: false,
        );

        return;
      }

      // Pre-flight token check using real-token ratios. Emits the "context
      // near limit" warning to the UI when within 8 % of the soft ceiling,
      // and auto-compacts the live chat if we already exceed it (so the
      // next turn does not blow past the KV ceiling and produce
      // "Input token ids are too long" again).
      final preflight = MessageLimits.estimatePromptTokens(
        model: model,
        systemPrompt: systemInstruction,
        query: query,
        ragContext: ragContext,
        attachmentContext: attachmentContext,
        historyTokenEstimate: historyTokenEstimate,
        hasVisionImage: hasVisionImage,
        highContext: _highContextEnabled,
        textToolPrompt: textToolPrompt,
        toolsCount: chatTools.length,
      );
      // Always publish so the chat status bar context meter stays current.
      _contextNearLimitController.add(preflight);
      if (preflight.isOverflow) {
        final ok = await _autoCompactForBudget(
          preflight,
          model,
          _lastReplaySource,
          inferenceModel,
          systemInstruction,
          chatTools,
        );
        if (!ok) {
          yield InferenceResult(
            text:
                '⚠️ Could not auto-compact chat history to fit '
                'within the model\'s context window. Try a shorter '
                'question, turn off High context in Settings, or reset '
                'inference.',
            model: model,
            isStreaming: false,
          );
          _isLoadingModel = false;
          return;
        }
      }

      final Message message;
      if (visionInput != null && hasVisionImage && _activeModelSupportsImage) {
        final visionBytes = await VisionImagePrep.prepareForInference(
          visionInput,
        );
        message = Message.withImage(
          text: query,
          imageBytes: visionBytes,
          isUser: true,
        );
      } else {
        message = Message.text(text: query, isUser: true);
      }

      try {
        await _activeChat!.addQuery(message);
      } catch (e) {
        _activeChat = null;
        _lastChatSessionKey = null;
        await _teardownPartialLoad();
        final err = e.toString();
        final isTokenOverflow =
            err.contains('too long') ||
            err.contains('INVALID_ARGUMENT') ||
            err.contains('Exceeding the maximum');
        final isImageUnsupported = err.contains('does not support image input');
        yield InferenceResult(
          text: isTokenOverflow
              ? '⚠️ This screenshot plus the system context is too large '
                    'for the model\'s context window. Try a shorter question, '
                    'turn off High context in Settings, or reset inference.'
              : isImageUnsupported
              ? '⚠️ The current model can\'t process images. Switch to a '
                    'vision model (FastVLM or Gemma 4) in Settings, or send '
                    'text-only input.'
              : '⚠️ Could not start inference.\n\n$e',
          model: model,
          isStreaming: false,
        );

        return;
      }

      String fullResponse = '';
      String? currentThinking;
      final textBuffer = StringBuffer();
      final inferenceStopwatch = Stopwatch()..start();

      // Tool call loop: after executing a tool, re-generate so the model
      // can incorporate the tool result into its response.
      bool hasPendingToolCalls = true;
      int toolRounds = 0;
      final List<Map<String, dynamic>> allToolCalls = [];
      final executedToolSignatures = <String>{};
      final lastToolResults = <String, Map<String, dynamic>>{};

      _isStreaming = true;
      _streamingCompleter = Completer<void>();

      // If the user already provided an image this turn, never re-capture.
      var imageAlreadyAvailable =
          (screenshot != null && screenshot.isNotEmpty) ||
          attachments.any(
            (a) => a.filePath != null && DocumentExtractor.isImageFile(a.name),
          );
      var screenshotToolCallsThisTurn = 0;

      Object? streamError;
      var safetyStopped = false;
      final maxOutputChars = GenerationSafety.maxOutputCharsFor(model);
      try {
        while (hasPendingToolCalls && toolRounds < _maxToolRounds) {
          hasPendingToolCalls = false;
          toolRounds++;

          await for (final event in _activeChat!.generateChatResponseAsync()) {
            if (_streamingCompleter?.isCompleted ?? false) {
              debugPrint('Stream aborted by stopGeneration / release');
              break;
            }
            if (event is TextResponse) {
              final token = event.token;
              fullResponse += token;
              textBuffer.write(token);

              final safetyMsg = GenerationSafety.safetyStopMessage(
                fullResponse,
                maxOutputChars,
              );
              if (safetyMsg != null) {
                safetyStopped = true;
                fullResponse = '$fullResponse$safetyMsg';
                yield InferenceResult(
                  text: _sanitizeAssistantText(fullResponse),
                  model: model,
                  isStreaming: true,
                  thinking: thinkingMode ? currentThinking : null,
                  toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
                );
                unawaited(stopGeneration());
                break;
              }

              // Try to parse function calls from the accumulated buffer.
              final parsedCalls = _tryParseFunctionCalls(textBuffer.toString());
              if (parsedCalls != null && parsedCalls.isNotEmpty) {
                fullResponse = _sanitizeAssistantText(fullResponse);
                textBuffer.clear();

                // Execute all tool calls found in this response
                for (final parsed in parsedCalls) {
                  final toolName = parsed['name'] as String;
                  final toolArgs = Map<String, dynamic>.from(
                    parsed['args'] as Map,
                  );
                  final signature = ToolCallParser.callSignature(
                    toolName,
                    toolArgs,
                  );

                  if (executedToolSignatures.contains(signature)) {
                    final dupResult = <String, dynamic>{
                      'success': true,
                      'message':
                          'Already called this turn with the same arguments. '
                          'Use the previous result. Do not call this tool again.',
                      if (lastToolResults[signature] != null)
                        'previous': lastToolResults[signature],
                    };
                    allToolCalls.add({
                      'name': toolName,
                      'args': toolArgs,
                      'result': dupResult,
                      'status': 'done',
                    });
                    await _activeChat!.addQuery(
                      Message.toolResponse(
                        toolName: toolName,
                        response: dupResult,
                      ),
                    );
                    hasPendingToolCalls = false;
                    continue;
                  }

                  // Block redundant screen captures when an image is already
                  // in context (attached photo / prior screenshot this turn).
                  if (toolName == 'take_screenshot' &&
                      (imageAlreadyAvailable ||
                          screenshotToolCallsThisTurn > 0)) {
                    allToolCalls.add({
                      'name': toolName,
                      'args': toolArgs,
                      'status': 'done',
                    });
                    await _activeChat!.addQuery(
                      Message.toolResponse(
                        toolName: toolName,
                        response: {
                          'success': true,
                          'message':
                              'An image is already available in this turn. '
                              'Describe that image. Do not call take_screenshot again.',
                        },
                      ),
                    );
                    executedToolSignatures.add(signature);
                    hasPendingToolCalls = true;
                    continue;
                  }

                  _statusController.add('Executing $toolName...');

                  allToolCalls.add({
                    'name': toolName,
                    'args': toolArgs,
                    'status': 'executing',
                  });

                  await for (final update in _executeToolWithProgress(
                    toolName,
                    toolArgs,
                    allToolCalls,
                    model,
                    currentThinking,
                    fullResponse,
                    thinkingMode,
                  )) {
                    yield update;
                  }

                  final completed = allToolCalls.isNotEmpty
                      ? allToolCalls.last['result']
                      : null;
                  if (completed is Map<String, dynamic>) {
                    lastToolResults[signature] = completed;
                  }
                  executedToolSignatures.add(signature);

                  if (toolName == 'take_screenshot') {
                    screenshotToolCallsThisTurn++;
                    imageAlreadyAvailable = true;
                  }

                  hasPendingToolCalls = true;
                }
              } else {
                yield InferenceResult(
                  text: _sanitizeAssistantText(fullResponse),
                  model: model,
                  isStreaming: true,
                  thinking: thinkingMode ? currentThinking : null,
                  toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
                );
              }
            } else if (event is ThinkingResponse) {
              currentThinking = event.content;
              yield InferenceResult(
                text: _sanitizeAssistantText(fullResponse),
                model: model,
                isStreaming: true,
                thinking: currentThinking,
                toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
              );
            } else if (event is FunctionCallResponse) {
              final normalized = ToolCallParser.normalizeCall({
                'name': event.name,
                'args': Map<String, dynamic>.from(event.args),
              });
              final toolName = normalized['name'] as String;
              final toolArgs = Map<String, dynamic>.from(
                normalized['args'] as Map,
              );
              final signature = ToolCallParser.callSignature(
                toolName,
                toolArgs,
              );

              if (executedToolSignatures.contains(signature)) {
                final dupResult = <String, dynamic>{
                  'success': true,
                  'message':
                      'Already called this turn with the same arguments. '
                      'Use the previous result. Do not call this tool again.',
                  if (lastToolResults[signature] != null)
                    'previous': lastToolResults[signature],
                };
                allToolCalls.add({
                  'name': toolName,
                  'args': toolArgs,
                  'result': dupResult,
                  'status': 'done',
                });
                await _activeChat!.addQuery(
                  Message.toolResponse(toolName: toolName, response: dupResult),
                );
                hasPendingToolCalls = false;
                continue;
              }

              if (toolName == 'take_screenshot' &&
                  (imageAlreadyAvailable || screenshotToolCallsThisTurn > 0)) {
                allToolCalls.add({
                  'name': toolName,
                  'args': toolArgs,
                  'status': 'done',
                });
                await _activeChat!.addQuery(
                  Message.toolResponse(
                    toolName: toolName,
                    response: {
                      'success': true,
                      'message':
                          'An image is already available in this turn. '
                          'Describe that image. Do not call take_screenshot again.',
                    },
                  ),
                );
                executedToolSignatures.add(signature);
                hasPendingToolCalls = true;
                continue;
              }

              // Plugin-level function call detected
              _statusController.add('Executing $toolName...');

              allToolCalls.add({
                'name': toolName,
                'args': toolArgs,
                'status': 'executing',
              });

              await for (final update in _executeToolWithProgress(
                toolName,
                toolArgs,
                allToolCalls,
                model,
                currentThinking,
                fullResponse,
                thinkingMode,
              )) {
                yield update;
              }

              final completed = allToolCalls.isNotEmpty
                  ? allToolCalls.last['result']
                  : null;
              if (completed is Map<String, dynamic>) {
                lastToolResults[signature] = completed;
              }
              executedToolSignatures.add(signature);

              if (toolName == 'take_screenshot') {
                screenshotToolCallsThisTurn++;
                imageAlreadyAvailable = true;
              }

              hasPendingToolCalls = true;
            }
          }
          if (safetyStopped || (_streamingCompleter?.isCompleted ?? false)) {
            hasPendingToolCalls = false;
            break;
          }
        }
      } on PlatformException catch (e) {
        streamError = e;
      } on Exception catch (e) {
        streamError = e;
      } finally {
        _isStreaming = false;
        if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
          _streamingCompleter!.complete();
        }
        _streamingCompleter = null;
        _onStreamEnded();
      }

      if (streamError != null) {
        final errText = streamError.toString();
        final isTokenOverflow =
            errText.contains('too long') ||
            errText.contains('INVALID_ARGUMENT') ||
            errText.contains('Exceeding the maximum');

        // Drop the dead chat so the next send rebuilds with a fresh session.
        _activeChat = null;
        _lastChatSessionKey = null;
        // For token overflow, shrink the pending replay to the last 2 turns so
        // the user's next send starts with a provably in-budget history
        // instead of the same over-budget payload.
        if (isTokenOverflow && _lastReplaySource.length > 2) {
          setPendingReplayMessages(
            _lastReplaySource.sublist(_lastReplaySource.length - 2),
          );
        }

        // #region agent log
        _debugLog(
          hypothesisId: 'B',
          location: 'model_orchestrator.dart:processMessage:streamError',
          message: 'Inference stream failed — dropping dead session',
          data: {
            'error': streamError.toString(),
            'model': model.name,
            'partialLen': fullResponse.length,
            'isTokenOverflow': isTokenOverflow,
          },
          runId: 'post-fix',
        );
        // #endregion
        inferenceStopwatch.stop();
        final hint = isTokenOverflow
            ? 'The prompt (screenshot + tools/context) exceeded the model '
                  'context window. Next send will use a shorter history — '
                  'try again, disable High context in Settings, or use '
                  'Settings → Reset inference.'
            : streamError.toString().contains('prefill') ||
                  streamError.toString().contains('Session')
            ? 'The model session broke (often after edit/regenerate). '
                  'Retry the message — a fresh session will be created.'
            : 'Try again. If it keeps failing: Settings → Reset inference.';
        yield InferenceResult(
          text: fullResponse.trim().isEmpty
              ? '⚠️ Inference failed.\n\n$hint\n\n$streamError'
              : '${_sanitizeAssistantText(fullResponse)}\n\n'
                    '⚠️ Inference interrupted.\n$hint',
          model: model,
          isStreaming: false,
          thinking: thinkingMode ? currentThinking : null,
          inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
        );

        return;
      }

      if (toolRounds >= _maxToolRounds && hasPendingToolCalls) {
        inferenceStopwatch.stop();
        final capped = _sanitizeAssistantText(fullResponse);
        yield InferenceResult(
          text: '$capped\n\n[Tool call limit reached]',
          model: model,
          isStreaming: false,
          thinking: thinkingMode ? currentThinking : null,
          inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
        );
        await MemoryService.storeConversation(query, capped);
        return;
      }

      inferenceStopwatch.stop();
      fullResponse = _sanitizeAssistantText(fullResponse);
      final userCancelled = _generationCancelledByUser;
      _generationCancelledByUser = false;

      // User stop with 0 tokens: UI already marked wasCancelled — do not
      // overwrite with a scary "empty response / stale session" warning.
      if (fullResponse.trim().isEmpty && userCancelled) {
        _activeChat = null;
        _lastChatSessionKey = null;
        yield InferenceResult(
          text: '',
          model: model,
          isStreaming: false,
          thinking: thinkingMode ? currentThinking : null,
          inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
        );

        return;
      }

      final reply = fullResponse.trim().isEmpty
          ? '⚠️ Model returned an empty response. '
                'Edit/regenerate may have left a stale session — try once more, '
                'or Settings → Reset inference.'
          : fullResponse;
      // #region agent log
      if (fullResponse.trim().isEmpty) {
        _debugLog(
          hypothesisId: 'C',
          location: 'model_orchestrator.dart:processMessage:emptyReply',
          message: 'Model finished with empty text',
          data: {'model': model.name, 'toolRounds': toolRounds},
          runId: 'post-fix',
        );
        // Drop polluted session so the next turn recreates cleanly.
        _activeChat = null;
        _lastChatSessionKey = null;
      }
      // #endregion
      yield InferenceResult(
        text: reply,
        model: model,
        isStreaming: false,
        thinking: thinkingMode ? currentThinking : null,
        inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
      );

      if (fullResponse.trim().isNotEmpty) {
        await MemoryService.storeConversation(query, fullResponse);
      }
    } finally {
      _releaseInferenceLock();
    }
  }

  /// Try to extract function calls from accumulated text.
  ///
  /// Handles JSON (`{"name":...}` / `tool_calls`) and ChatML-ish markup such as
  /// `<|tool_call>call:google_search{queries:[...]}` (aliased to `search_web`).
  List<Map<String, dynamic>>? _tryParseFunctionCalls(String text) {
    return ToolCallParser.parse(text);
  }

  /// Drop raw tool markup from assistant text shown in the UI.
  String _sanitizeAssistantText(String text) {
    return ToolCallParser.stripMarkup(text);
  }

  /// Execute a tool with progress streaming. Returns a stream of
  /// [InferenceResult] updates that the caller should yield from.
  Stream<InferenceResult> _executeToolWithProgress(
    String toolName,
    Map<String, dynamic> toolArgs,
    List<Map<String, dynamic>> allToolCalls,
    NovaModel model,
    String? currentThinking,
    String fullResponse,
    bool thinkingMode,
  ) async* {
    // Subscribe to native progress events
    final progressSub = ToolExecutorService.instance.onProgress
        .where((p) => p.toolName == toolName)
        .listen((progress) {
          // Update the tool call entry with progress info
          if (allToolCalls.isNotEmpty) {
            allToolCalls.last['progress'] = progress.message;
            allToolCalls.last['progressPercent'] = progress.percent;
            allToolCalls.last['progressStage'] = progress.stage.name;
          }
        });

    // Also yield our own starting event
    if (allToolCalls.isNotEmpty) {
      allToolCalls.last['progress'] = 'Starting $toolName...';
    }
    yield InferenceResult(
      text: _sanitizeAssistantText(fullResponse),
      model: model,
      isStreaming: true,
      thinking: thinkingMode ? currentThinking : null,
      toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
    );

    Map<String, dynamic> toolResult;
    try {
      // Route task and note tools to Dart services
      const dartTools = {
        'create_task',
        'list_tasks',
        'complete_task',
        'create_note',
        'search_notes',
        'list_notes',
      };
      final normalized = ToolCallParser.normalizeCall({
        'name': toolName,
        'args': toolArgs,
      });
      final resolvedName = normalized['name'] as String;
      final resolvedArgs = Map<String, dynamic>.from(normalized['args'] as Map);

      if (resolvedName == 'generate_image') {
        final prompt = resolvedArgs['prompt'] as String? ?? '';
        final sizeInt = (resolvedArgs['size'] as int?) ?? 512;
        final size = switch (sizeInt) {
          256 => ImageSize.size256,
          1024 => ImageSize.size1024,
          _ => ImageSize.size512,
        };
        final seed = resolvedArgs['seed'] as int?;
        final modelName = resolvedArgs['model'] as String?;
        final model = modelName != null
            ? DiffusionModel.values.firstWhere(
                (m) => m.name == modelName,
                orElse: () => DiffusionModel.zImageTurbo,
              )
            : null;

        final installed = await ImageGenerationService.instance
            .isModelInstalled(model);
        if (!installed) {
          toolResult = <String, dynamic>{
            'success': false,
            'error': 'no_model',
            'message':
                'No diffusion model installed. '
                'Download Z-Image-Turbo (~800MB) or FLUX.2-klein (~2.4GB) '
                'in Settings to generate images.',
          };
        } else {
          final imageBytes = await ImageGenerationService.instance
              .generateImage(prompt, size: size, seed: seed, model: model);

          toolResult = <String, dynamic>{
            'success': imageBytes != null && imageBytes.isNotEmpty,
            if (imageBytes != null && imageBytes.isNotEmpty)
              'imageBytes': imageBytes,
          };
        }
      } else if (dartTools.contains(resolvedName)) {
        if ([
          'create_task',
          'list_tasks',
          'complete_task',
        ].contains(resolvedName)) {
          toolResult = await TaskService.instance.executeTool(
            resolvedName,
            resolvedArgs,
          );
        } else {
          toolResult = await NoteService.instance.executeTool(
            resolvedName,
            resolvedArgs,
          );
        }
      } else {
        // Try MCP external tools first, then native tools
        ExternalToolResult? mcpResult;
        if (McpService.instance.getTool(resolvedName) != null) {
          mcpResult = await McpService.instance.executeTool(
            resolvedName,
            resolvedArgs,
          );
        }

        if (mcpResult != null) {
          toolResult = mcpResult.toJson();
        } else {
          toolResult = await ToolExecutorService.instance.executeTool(
            resolvedName,
            resolvedArgs,
          );
        }
      }
    } finally {
      await progressSub.cancel();
    }

    // Update with completion
    if (allToolCalls.isNotEmpty) {
      allToolCalls.last['status'] = 'done';
      allToolCalls.last['result'] = toolResult;
      allToolCalls.last['progress'] = null;
      allToolCalls.last['progressPercent'] = null;
    }

    // Yield final state with completed tool
    yield InferenceResult(
      text: _sanitizeAssistantText(fullResponse),
      model: model,
      isStreaming: true,
      thinking: thinkingMode ? currentThinking : null,
      toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
      imageBytes: toolResult['imageBytes'] as Uint8List?,
    );

    await _sendToolResponse(
      ToolCallParser.normalizeCall({'name': toolName, 'args': toolArgs})['name']
          as String,
      toolResult,
    );
  }

  /// Send a tool response to the model. For [take_screenshot], the image
  /// bytes are injected as a [Message.withImage] so the vision model can
  /// actually see the screenshot — raw bytes in a text tool response are
  /// invisible to the model.
  Future<void> _sendToolResponse(
    String toolName,
    Map<String, dynamic> toolResult,
  ) async {
    // If _activeChat is null (e.g., due to model switch during tool execution),
    // skip sending the response - the new model will handle things
    if (_activeChat == null) {
      debugPrint('Tool response skipped: _activeChat is null');
      return;
    }

    if (toolName == 'take_screenshot') {
      // Prefer the dedicated screenshot channel (returns Uint8List directly).
      // Tool MethodChannel maps drop/corrupt large ByteArray payloads.
      await ScreenshotService.instance.requestCapture();
      Uint8List? imageBytes = await ScreenshotService.instance
          .getLatestScreenshot();
      // #region agent log
      _debugLog(
        hypothesisId: 'H12',
        location: 'model_orchestrator.dart:_sendToolResponse',
        message: 'take_screenshot after requestCapture+getLatest',
        data: {
          'toolSuccess': toolResult['success'],
          'toolHasScreenshot': toolResult['hasScreenshot'],
          'toolBytes': toolResult['bytes'],
          'channelBytes': imageBytes?.length ?? 0,
          'supportsImage': _activeModelSupportsImage,
        },
        runId: 'post-fix',
      );
      // #endregion

      final data = toolResult['data'];
      if ((imageBytes == null || imageBytes.isEmpty) && data != null) {
        if (data is Uint8List) {
          imageBytes = data;
        } else if (data is List<int>) {
          imageBytes = Uint8List.fromList(data);
        }
      }

      if (imageBytes != null &&
          imageBytes.isNotEmpty &&
          _activeModelSupportsImage) {
        final visionBytes = await VisionImagePrep.prepareForInference(
          imageBytes,
        );
        final imageMessage = Message.withImage(
          text: '[Screenshot captured]',
          imageBytes: visionBytes,
          isUser: true,
        );
        await _activeChat!.addQuery(imageMessage);
        // #region agent log
        _debugLog(
          hypothesisId: 'H8',
          location: 'model_orchestrator.dart:_sendToolResponse',
          message: 'vision image attached to chat',
          data: {'imageBytes': visionBytes.length},
          runId: 'post-fix',
        );
        // #endregion
      }

      final toolResponseMessage = Message.toolResponse(
        toolName: toolName,
        response: {
          'success': imageBytes != null && imageBytes.isNotEmpty,
          if (imageBytes != null && imageBytes.isNotEmpty)
            'message': 'Image generated and displayed above'
          else
            'message': 'Image generation failed — model may not be installed',
        },
      );
      await _activeChat!.addQuery(toolResponseMessage);
    } else if (toolName == 'generate_image') {
      Uint8List? imageBytes;
      final raw = toolResult['imageBytes'];
      if (raw is Uint8List) {
        imageBytes = raw;
      } else if (raw is List<int>) {
        imageBytes = Uint8List.fromList(raw);
      }

      if (imageBytes != null && imageBytes.isNotEmpty) {
        final displayMessage = Message.withImage(
          text: '[Generated image]',
          imageBytes: imageBytes,
          isUser: false,
        );
        await _activeChat!.addQuery(displayMessage);
      }

      final toolResponseMessage = Message.toolResponse(
        toolName: toolName,
        response: Map<String, dynamic>.from(toolResult),
      );
      await _activeChat!.addQuery(toolResponseMessage);
    } else {
      final toolResponseMessage = Message.toolResponse(
        toolName: toolName,
        response: Map<String, dynamic>.from(toolResult),
      );
      await _activeChat!.addQuery(toolResponseMessage);
    }
  }

  Future<String> _languageInstruction() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    final language = AssistantLanguage.fromString(
      _cachedPrefs!.getString(AssistantLanguage.prefsKey),
    );

    return language.systemPromptLine;
  }

  Future<String> _systemPromptFor(
    NovaModel model, [
    String? ragContext,
    String? attachmentContext,
    List<Tool>? textTools,
  ]) async {
    final compact =
        model == NovaModel.smollm ||
        (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            model == NovaModel.gemma4E2b);

    final identity = _getCachedIdentity();

    String base;
    if (identity != null && identity.name != 'Nova') {
      base = compact
          ? identity.buildCompactSystemPrompt()
          : identity.buildSystemPrompt();
    } else {
      base = compact
          ? _getAssistantRole().compactSystemPrompt
          : _getAssistantRole().systemPrompt;
    }

    final thinkingSuffix = model.hasThinking && !compact
        ? ' When asked to think step by step, show your reasoning in <thinking> tags '
              'before your final answer.'
        : '';

    // Adult mode leads the prompt so refusal priors cannot bury it at the end.
    final buffer = StringBuffer();
    if (_adultModeEnabled) {
      buffer.write(AdultModePolicy.systemPromptLead(compact: compact));
    }
    buffer.write('$base$thinkingSuffix');
    if (!compact) {
      buffer.write('\n\n${await _languageInstruction()}');
    }

    // Compact Android prompts drop the role's tool list. Only restore the
    // capability suffix when native FC is unavailable AND we actually have a
    // non-empty tool list to describe — otherwise every Gemma 4 Android turn
    // pays ~500 chars / ~120 tokens of sermon it never reads.
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final hasTextTools = textTools != null && textTools.isNotEmpty;
    if (isAndroid && model != NovaModel.smollm && (!compact || hasTextTools)) {
      buffer.write(
        _deviceToolsCapabilitySuffix(hasTextTools ? textTools : null),
      );
    }

    if (_adultModeEnabled) {
      buffer.write(AdultModePolicy.systemPromptSuffix(compact: compact));
    }

    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.write('\n\n${_capContextInjection(ragContext)}');
    }

    if (attachmentContext != null && attachmentContext.isNotEmpty) {
      buffer.write(
        '\n\n--- Attached Data ---\n${_capContextInjection(attachmentContext)}',
      );
    }

    if (!compact) {
      // Add data source context from MCP sources
      final enabledSources = McpService.instance.sources
          .where((s) => s.enabled)
          .toList();
      if (enabledSources.isNotEmpty) {
        buffer.write('\n\n--- Connected Data Sources ---');
        for (final source in enabledSources) {
          buffer.write('\n- ${source.name}: ${source.description}');
        }
      }
    }

    return buffer.toString();
  }

  /// Short capability block for on-device tools (and text-JSON FC when native FC
  /// is unavailable on Android Gemma 4).
  String _deviceToolsCapabilitySuffix(List<Tool>? textTools) {
    final names = (textTools ?? const <Tool>[])
        .map((t) => t.name)
        .where((n) => n.isNotEmpty)
        .toList();
    final listed = names.isEmpty
        ? 'get_time, set_alarm, cancel_alarm, open_app, open_settings, search_web, generate_image'
        : names.join(', ');

    return ' You control this Android device via tools: $listed. '
        'When the user asks to open an app, set/cancel an alarm, open settings, '
        'search the web, or generate an image, call the matching tool immediately — '
        'do not say you lack device access. '
        'Use exact tool names only ($listed). Never invent names like '
        'google_search. '
        'open_app: if the user types a full package id '
        '(e.g. app.revanced.android.youtube), use that exact package — '
        'do not substitute com.google.android.youtube. '
        'Aliases: youtube→com.google.android.youtube, '
        'revanced/morphe→app.revanced.android.youtube, '
        'settings→com.android.settings, chrome→com.android.chrome. '
        'If you must emit text instead of native function calling, reply with '
        'only JSON like '
        '{"name":"search_web","arguments":{"query":"Missypwns twitch"}}.';
  }

  Stream<InferenceResult> _processRemoteMessage({
    required String query,
    required String ragContext,
    required String attachmentContext,
    required List<Tool> tools,
  }) async* {
    if (kIsWeb) {
      yield InferenceResult(
        text:
            'Remote LAN inference is not available on web. '
            'Switch to On-device in Settings → Remote LAN inference.',
        model: selector.primaryHeavy,
        isStreaming: false,
      );

      return;
    }

    if (tools.isNotEmpty) {
      _statusController.add(
        'Tools unavailable on remote backend (local shortcuts still work)',
      );
    }

    _statusController.add('Connecting to LAN model...');
    _isStreaming = true;
    final client = RemoteInferenceClient();
    final buffer = StringBuffer();
    final sw = Stopwatch()..start();

    try {
      final systemPrompt = await _systemPromptFor(
        selector.primaryHeavy,
        ragContext.isEmpty ? null : ragContext,
        attachmentContext.isEmpty ? null : attachmentContext,
      );

      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        ..._pendingReplay
            .where((m) => m.text.trim().isNotEmpty)
            .map(
              (m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              },
            ),
        {'role': 'user', 'content': query},
      ];

      await for (final delta in client.streamChat(
        config: _remoteConfig,
        messages: messages,
      )) {
        buffer.write(delta);
        yield InferenceResult(
          text: buffer.toString(),
          model: selector.primaryHeavy,
          isStreaming: true,
        );
      }

      sw.stop();
      yield InferenceResult(
        text: buffer.toString().isEmpty
            ? '⚠️ Empty response from remote host.'
            : buffer.toString(),
        model: selector.primaryHeavy,
        isStreaming: false,
        inferenceTimeMs: sw.elapsedMilliseconds,
      );
    } on Exception catch (e) {
      yield InferenceResult(
        text:
            '⚠️ Remote inference failed: $e\n\n'
            'Check Settings → Remote LAN inference (base URL, model id, Wi‑Fi).',
        model: selector.primaryHeavy,
        isStreaming: false,
      );
    } finally {
      _isStreaming = false;
      client.close();
      _statusController.add('Ready');
    }
  }

  static AgentIdentity? _cachedIdentity;

  static AgentIdentity? _getCachedIdentity() => _cachedIdentity;

  static AssistantRole _getAssistantRole() {
    return _cachedRole;
  }

  static AssistantRole _cachedRole = AssistantRole.helpful;

  Future<void> _loadAssistantRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleName = prefs.getString('settings_assistant_role');
    _cachedRole = AssistantRole.fromString(roleName);
  }

  Future<String?> _findModelPath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final directFile = File('${dir.path}/$fileName');
    if (await directFile.exists()) {
      return directFile.path;
    }
    final modelsDir = Directory('${dir.path}/models');
    if (await modelsDir.exists()) {
      await for (final entity in modelsDir.list()) {
        if (entity is File &&
            entity.path.contains(
              fileName.replaceAll('.litertlm', '').replaceAll('.task', ''),
            )) {
          return entity.path;
        }
      }
    }
    return null;
  }

  Future<void> clearHistory() async {
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
    _activeChat = null;
    _lastChatSessionKey = null;
    _pendingReplay = const [];
    _lastReplaySource = const [];
    ConversationSummaryService.instance.activeSummary = null;
    // Keep preferred / custom model pinned across history wipe.
    await ChatHistoryService.clear();
    _historyClearedController.add(null);
  }

  Future<void> close() async {
    try {
      await _activeModel?.close();
    } catch (e) {
      debugPrint('ModelOrchestrator.close: error closing active model: $e');
    }
    _activeModel = null;
    _activeChat = null;
    _activeModelType = null;
    _activeModelMaxTokens = null;
    _activeModelSupportsImage = false;
    _isInitialized = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _stopModelKeepAlive();
    await _clearActiveInferenceIdentity();
    await _statusController.close();
    await _historyClearedController.close();
    await _contextNearLimitController.close();
  }

  Future<void> _clearActiveInferenceIdentity() async {
    if (!FlutterGemma.hasActiveModel()) return;
    try {
      await FlutterGemma.clearActiveInferenceIdentity();
    } catch (e) {
      debugPrint('Error clearing active inference identity: $e');
    }
  }

  /// Initialize settings without loading any model.
  /// Model loading is deferred until first use to prevent startup resource exhaustion.
  Future<void> initializeDefaultModel() async {
    await _loadAssistantRole();
    await _loadPreferredModel();
    await _loadRuntimeSettings();
    await _loadIdentity();
    _startBatteryCheck();
    await applyRamAwareModelDefaults();
    // NOTE: We deliberately do NOT load a model here.
    // Loading a 2.4GB model at startup causes memory/CPU exhaustion
    // on some devices, leading to crashes. Models are loaded lazily
    // when the user actually sends a message.
  }

  Future<void> _loadIdentity() async {
    _cachedIdentity = await IdentityService.getIdentity();
  }

  /// Call this when assistant role or identity changes in settings
  static Future<void> refreshSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final roleName = prefs.getString('settings_assistant_role');
    _cachedRole = AssistantRole.fromString(roleName);
    _cachedIdentity = await IdentityService.getIdentity();
    await instance._loadRuntimeSettings(invalidateChatOnAdultChange: true);
  }

  /// Pre-warms the default model at app startup (opt-in via settings).
  /// Loads the model into memory so the first response is instant.
  /// Does not create a chat session — that happens on first message.
  static Future<void> warmUpDefaultModel() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('settings_prewarm_model') ?? false;
    if (!enabled) return;

    final orch = instance;
    if (orch._activeModel != null) return;

    final defaultModel = orch.preferredModelType ?? orch.selector.primaryHeavy;

    if (kIsWeb) return;

    try {
      debugPrint('Pre-warming model: ${defaultModel.displayName}');
      await orch._getOrCreateModel(defaultModel);
      debugPrint('Pre-warmed: ${defaultModel.displayName}');
      orch._startModelKeepAlive(defaultModel.displayName);
    } catch (e) {
      debugPrint('Pre-warm failed (non-critical): $e');
    }
  }
}

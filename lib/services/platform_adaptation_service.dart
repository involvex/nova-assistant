import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/memory_diagnostics_service.dart';

/// Platform-specific feature capabilities
class PlatformCapabilities {
  final bool supportsVision;
  final bool supportsThinking;
  final bool supportsFunctionCalling;
  final bool supportsStreaming;
  final bool supportsParallelSessions;
  final String platformName;

  const PlatformCapabilities({
    required this.supportsVision,
    required this.supportsThinking,
    required this.supportsFunctionCalling,
    required this.supportsStreaming,
    required this.supportsParallelSessions,
    required this.platformName,
  });

  /// Get capabilities for the current platform
  static PlatformCapabilities get current {
    if (kIsWeb) {
      return const PlatformCapabilities(
        supportsVision: false, // Web litertlm doesn't support vision yet
        supportsThinking: false, // Web litertlm doesn't support thinking yet
        supportsFunctionCalling:
            false, // Web litertlm doesn't support function calling yet
        supportsStreaming: true,
        supportsParallelSessions: true,
        platformName: 'web',
      );
    }

    // Cap parallel sessions on Android — multiple chats × large KV is unsafe
    // on mid/low-RAM devices (e.g. Poco F1).
    final parallelOk = defaultTargetPlatform != TargetPlatform.android;

    // Native platforms (Android, iOS, macOS, Windows, Linux)
    return PlatformCapabilities(
      supportsVision: true,
      supportsThinking: true,
      supportsFunctionCalling: true,
      supportsStreaming: true,
      supportsParallelSessions: parallelOk,
      platformName: 'native',
    );
  }

  /// Check if a specific feature is supported
  bool supportsFeature(ModelFeature feature) {
    switch (feature) {
      case ModelFeature.vision:
        return supportsVision;
      case ModelFeature.thinking:
        return supportsThinking;
      case ModelFeature.functionCalling:
        return supportsFunctionCalling;
      case ModelFeature.streaming:
        return supportsStreaming;
      case ModelFeature.parallelSessions:
        return supportsParallelSessions;
    }
  }

  /// Get unsupported features for a model
  List<ModelFeature> getUnsupportedFeatures(NovaModel model) {
    final unsupported = <ModelFeature>[];

    if (model.hasVision && !supportsVision) {
      unsupported.add(ModelFeature.vision);
    }
    if (model.hasThinking && !supportsThinking) {
      unsupported.add(ModelFeature.thinking);
    }
    if (!supportsFunctionCalling) {
      unsupported.add(ModelFeature.functionCalling);
    }

    return unsupported;
  }
}

/// Model features that may have platform limitations
enum ModelFeature {
  vision,
  thinking,
  functionCalling,
  streaming,
  parallelSessions,
}

/// Adaptation for web platform limitations
class WebAdaptation {
  final String feature;
  final String limitation;
  final String? workaround;
  final bool isBlocker;

  const WebAdaptation({
    required this.feature,
    required this.limitation,
    this.workaround,
    this.isBlocker = false,
  });
}

/// Service for handling platform-specific adaptations
class PlatformAdaptationService {
  static PlatformAdaptationService? _instance;
  static PlatformAdaptationService get instance =>
      _instance ??= PlatformAdaptationService._();
  PlatformAdaptationService._();

  final PlatformCapabilities _capabilities = PlatformCapabilities.current;
  PlatformCapabilities get capabilities => _capabilities;

  /// Get web-specific adaptations for a model
  List<WebAdaptation> getWebAdaptations(NovaModel model) {
    if (!kIsWeb) return [];

    final adaptations = <WebAdaptation>[];

    if (model.hasVision) {
      adaptations.add(
        const WebAdaptation(
          feature: 'Vision/Image Input',
          limitation: 'Web litertlm does not support vision executor',
          workaround: 'Use MediaPipe .task models for web vision support',
          isBlocker: true,
        ),
      );
    }

    if (model.hasThinking) {
      adaptations.add(
        const WebAdaptation(
          feature: 'Thinking Mode',
          limitation:
              'Web litertlm does not support extraContext thinking channel',
          workaround: 'Use MediaPipe .task models for thinking support',
          isBlocker: true,
        ),
      );
    }

    adaptations.add(
      const WebAdaptation(
        feature: 'Function Calling',
        limitation: 'Web litertlm does not support tool calls',
        workaround: 'Use MediaPipe .task models for function calling',
        isBlocker: true,
      ),
    );

    adaptations.add(
      const WebAdaptation(
        feature: 'Model Storage',
        limitation: 'Chrome has ~2GB ArrayBuffer limit',
        workaround: 'Use WebStorageMode.streaming for large models via OPFS',
        isBlocker: false,
      ),
    );

    return adaptations;
  }

  /// Get the recommended model for web platform
  NovaModel getRecommendedWebModel({
    bool needsVision = false,
    bool needsThinking = false,
    bool needsFunctionCalling = false,
  }) {
    if (!kIsWeb) {
      // On native, return the best model for the requirements
      if (needsVision || needsThinking || needsFunctionCalling) {
        return NovaModel.gemma4E2b;
      }
      return NovaModel.smollm;
    }

    // On web, only SmolLM and Gemma 3 1B work well
    // (Gemma 4 E2B requires streaming mode for large models)
    if (needsVision) {
      // Vision not supported on web litertlm, suggest MediaPipe alternative
      return NovaModel.fastvlm; // Will show warning about limitations
    }

    if (needsThinking || needsFunctionCalling) {
      // Not supported on web litertlm
      return NovaModel.gemma3_1b; // Will show warning about limitations
    }

    return NovaModel.smollm;
  }

  /// Get storage mode recommendation for web
  String getWebStorageRecommendation(int modelSizeMB) {
    if (!kIsWeb) return 'native';

    if (modelSizeMB > 2000) {
      return 'streaming'; // Use OPFS for large models
    } else if (modelSizeMB > 500) {
      return 'cacheApi'; // Use Cache API for medium models
    } else {
      return 'cacheApi'; // Cache API works fine for small models
    }
  }

  /// Get platform-specific error message
  String getPlatformError(String error, NovaModel model) {
    if (!kIsWeb) return error;

    if (error.contains('vision') || error.contains('image')) {
      return 'Vision is not supported on web platform. '
          'Use MediaPipe .task models for image input.';
    }

    if (error.contains('thinking') || error.contains('extraContext')) {
      return 'Thinking mode is not supported on web platform. '
          'Use MediaPipe .task models for thinking support.';
    }

    if (error.contains('tool') || error.contains('function')) {
      return 'Function calling is not supported on web platform. '
          'Use MediaPipe .task models for tool support.';
    }

    if (error.contains('lora') || error.contains('LoRA')) {
      return 'LoRA weights are not supported on web platform.';
    }

    return error;
  }

  /// Check if a model is compatible with the current platform
  bool isModelCompatible(NovaModel model) {
    if (!kIsWeb) return true;

    // On web, only litertlm models work
    // SmolLM and Gemma 3 1B are safe choices
    return model == NovaModel.smollm || model == NovaModel.gemma3_1b;
  }

  /// Get platform-specific initialization parameters
  Map<String, dynamic> getInitializationParams() {
    if (kIsWeb) {
      return {'webStorageMode': 'cacheApi', 'maxDownloadRetries': 5};
    }

    return {'maxDownloadRetries': 10};
  }

  /// Get GPU backend recommendation
  String getBackendRecommendation() {
    if (kIsWeb) {
      return 'gpu'; // Web only supports GPU
    }

    return 'gpu'; // Prefer GPU on native too
  }

  /// Prefer GPU; large models still use GPU but emit a memory warning via
  /// [getMemoryWarning]. (CPU is available as a future low-RAM fallback.)
  PreferredBackend preferredBackendFor(NovaModel model) {
    if (kIsWeb) return PreferredBackend.gpu;
    // Keep GPU for quality/latency; RAM is controlled by idle unload +
    // clearActiveInferenceIdentity rather than forcing CPU here.
    return PreferredBackend.gpu;
  }

  /// Get memory warning for large models
  String? getMemoryWarning(NovaModel model) {
    if (kIsWeb) {
      if (model.sizeMB > 2000) {
        return 'Large models may hit browser memory limits. '
            'Consider using a smaller model for better performance.';
      }
    }

    if (model.sizeMB >= 2000) {
      return 'This model needs ~${model.sizeMB} MB on disk plus GPU runtime '
          'memory. On devices with ≤6 GB RAM (e.g. mid-range phones), prefer '
          'SmolLM or Gemma 3 1B for soak testing to avoid system LMK killing '
          'other apps. Close background apps before loading.';
    }

    return null;
  }

  /// Minimum free system RAM (MB) required before a cold load of [model].
  /// Returns null when no hard gate applies (small models / non-Android).
  int? minFreeRamMbFor(NovaModel model) {
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    if (model.sizeMB >= 2000) return 3500;
    if (model.sizeMB >= 400) return 1200;

    return null;
  }

  /// Pure gate check: returns an error message when [availMemMb] is too low.
  String? freeRamGateMessage({
    required NovaModel model,
    required int? availMemMb,
  }) {
    final minFree = minFreeRamMbFor(model);
    if (minFree == null || availMemMb == null) return null;
    if (availMemMb >= minFree) return null;

    return 'Not enough free RAM to load ${model.displayName} '
        '($availMemMb MB free, need ~$minFree MB). '
        'Close background apps or switch to SmolLM / Gemma 3 1B.';
  }

  /// Async hard gate using [MemoryDiagnosticsService] free-RAM reading.
  Future<String?> checkCanLoadModel(NovaModel model) async {
    final minFree = minFreeRamMbFor(model);
    if (minFree == null) return null;

    final avail = await MemoryDiagnosticsService.instance.readAvailableMemMb();

    return freeRamGateMessage(model: model, availMemMb: avail);
  }

  /// Max parallel chat sessions for the current platform.
  int get maxParallelSessions {
    if (!_capabilities.supportsParallelSessions) return 1;

    return 3;
  }
}

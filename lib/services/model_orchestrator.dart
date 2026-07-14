import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/attached_data.dart';
import 'package:nova_assistant/models/agent_identity.dart';
import 'package:nova_assistant/models/assistant_role.dart';
import 'package:nova_assistant/models/external_tool.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/platform/tool_executor_service.dart';

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

  InferenceResult({
    required this.text,
    required this.model,
    this.isStreaming = false,
    this.thinking,
    this.toolCalls,
    this.inferenceTimeMs,
  });
}

class ModelOrchestrator {
  static final ModelOrchestrator instance = ModelOrchestrator._();
  ModelOrchestrator._();

  static const _prefsKey = 'preferred_model_override';

  final ModelSelector selector = ModelSelector(
    primaryHeavy: NovaModel.gemma4E2b,
    fastModel: NovaModel.smollm,
  );

  InferenceModel? _activeModel;
  InferenceChat? _activeChat;
  NovaModel? _activeModelType;
  bool _activeModelSupportsImage = false;
  NovaModel? _preferredModelOverride;
  CustomModel? _preferredCustomModelOverride;
  bool _modelOverrideDirty = false;
  bool _isInitialized = false;
  bool _batteryOptimizationEnabled = true;
  bool _debugMode = false;
  bool _isReleasing = false; // Guard against concurrent release operations
  Completer<void>? _releaseCompleter; // Signals when release is complete
  Timer? _idleTimer;
  bool _isStreaming = false;
  Completer<void>? _streamingCompleter;
  static const _defaultIdleTimeout = Duration(minutes: 5);

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _historyClearedController = StreamController<void>.broadcast();
  Stream<void> get historyClearedStream => _historyClearedController.stream;

  bool get isInitialized => _isInitialized;

  void setBatteryOptimization(bool enabled) {
    _batteryOptimizationEnabled = enabled;
    if (!enabled) {
      _idleTimer?.cancel();
      _idleTimer = null;
    } else {
      _resetIdleTimer();
    }
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
    _activeChat = null;
    if (_activeModel != null &&
        (_activeModelType == null ||
            model == null ||
            model != _activeModelType)) {
      _activeModel!.close().catchError((_) {});
      _activeModel = null;
    }
    _persistPreferredModel(model);
  }

  CustomModel? get preferredCustomModel => _preferredCustomModelOverride;

  set preferredCustomModel(CustomModel? model) {
    if (_preferredCustomModelOverride?.id == model?.id) return;
    _preferredCustomModelOverride = model;
    _preferredModelOverride = null;
    _modelOverrideDirty = true;
    _activeChat = null;
    if (_activeModel != null) {
      _activeModel!.close().catchError((_) {});
      _activeModel = null;
    }
  }

  Future<void> _persistPreferredModel(NovaModel? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (model == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, model.name);
    }
  }

  Future<void> _loadPreferredModel() async {
    final prefs = await SharedPreferences.getInstance();
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

  void clearModelOverride() {
    _preferredModelOverride = null;
    _preferredCustomModelOverride = null;
    _modelOverrideDirty = false;
  }

  void refreshModelOverride() {
    if (_preferredModelOverride != null) {
      _modelOverrideDirty = true;
    }
  }

  void _resetIdleTimer() {
    if (!_batteryOptimizationEnabled) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(_defaultIdleTimeout, _releaseIdleResources);
  }

  Future<void> _releaseIdleResources() async {
    if (_isReleasing) {
      debugPrint('Release already in progress, skipping');
      return;
    }
    _isReleasing = true;
    _releaseCompleter = Completer<void>();

    try {
      if (!_batteryOptimizationEnabled) return;

      // Signal any active stream to abort
      if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
        _streamingCompleter!.complete();
      }

      // Clear the chat reference
      if (_activeChat != null) {
        try {
          _activeChat = null;
        } catch (_) {}
      }

      // Wait for any ongoing stream iteration to finish
      if (_isStreaming) {
        debugPrint('Waiting for active stream to finish...');
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (_isStreaming && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (_isStreaming) {
          debugPrint('Stream did not finish in time, forcing release');
        }
      }

      // Now close the model
      if (_activeModel != null) {
        try {
          await _activeModel!.close();
        } catch (e) {
          debugPrint('Error closing model: $e');
        }
      }
      _activeModel = null;
      _activeModelSupportsImage = false;

      _statusController.add('Idle — model released to save battery');
    } catch (e) {
      debugPrint('Error releasing idle resources: $e');
    } finally {
      _isReleasing = false;
      _releaseCompleter?.complete();
      _releaseCompleter = null;
    }
  }

  Future<void> releaseIdleResources() => _releaseIdleResources();

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

    for (final model in NovaModel.values) {
      final fileName = ModelHuggingFaceURLs.fileNameFor(model);

      // Find the file on disk using the unified search
      File? foundFile;
      final directFile = File('${dir.path}/$fileName');
      if (await directFile.exists()) {
        foundFile = directFile;
      } else {
        final modelsDir = Directory('${dir.path}/models');
        if (await modelsDir.exists()) {
          final baseName =
              fileName.replaceAll('.litertlm', '').replaceAll('.task', '');
          await for (final entity in modelsDir.list()) {
            if (entity is File) {
              final entityName = p.basename(entity.path);
              if (entityName
                  .replaceAll('.litertlm', '')
                  .replaceAll('.task', '')
                  .contains(baseName)) {
                foundFile = entity;
                break;
              }
            }
          }
        }
      }

      if (foundFile != null) {
        // Already tracked but file exists - try to verify it's not corrupted
        if (ModelManager.instance.isModelInstalled(fileName)) {
          try {
            // Verify by trying to create a chat (this validates the model loads)
            // Don't call install() as it may re-register an already registered model
            // Instead, just verify the file can be read and is non-empty
            final fileSize = await foundFile.length();
            if (fileSize == 0) {
              throw Exception('Model file is empty');
            }
            // File exists and has content - assume valid until flutter_gemma says otherwise
            _statusController.add('Model ${model.displayName} verified');
          } catch (e) {
            // Model health check failed - remove from installed and delete file
            debugPrint('Model health check failed for $fileName: $e');
            await ModelManager.instance.uninstallModel(fileName);
            try {
              await foundFile.delete();
              _statusController.add('Removed corrupt model: $fileName');
            } catch (_) {}
          }
        } else {
          // Not tracked yet - register it
          await ModelManager.instance.registerDiskModel(
            filePath: foundFile.path,
            fileName: fileName,
            modelType: model.modelType,
            fileType: model.fileType,
            fileSizeBytes: await foundFile.length(),
          );
        }
      } else if (ModelManager.instance.isModelInstalled(fileName)) {
        // Model is tracked but file doesn't exist - remove from tracking
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

    final needsImageSupport = model.hasVision && screenshot != null;

    // Return cached model if same type AND image support setting matches
    if (_activeModel != null &&
        _activeModelType == model &&
        _activeModelSupportsImage == needsImageSupport) {
      return _activeModel!;
    }

    // --- Switching / Loading new model ---
    // Close any previous model and clear flutter_gemma's active identity.
    // We must ALWAYS do this when loading a new model because:
    // 1. On restart, _activeModelType is null but flutter_gemma may have a
    //    cached model from a prior session (wrong type for what we need)
    // 2. flutter_gemma.getActiveModel() returns whatever is cached internally
    //    — if it's a different model type, we get wrong behavior
    // Clearing ensures getActiveModel() loads the correct model fresh.
    if (_activeModel != null) {
      try {
        await _activeModel!.close();
      } catch (e) {
        debugPrint('Error closing previous model: $e');
      }
      _activeModel = null;
      _activeChat = null;
    }

    // Clear flutter_gemma's internal state if we might have a different model cached
    // This ensures getActiveModel() loads the correct model fresh
    if (FlutterGemma.hasActiveModel()) {
      // If we're loading a different model type, clear first
      if (_activeModelType != model) {
        try {
          await FlutterGemma.clearActiveInferenceIdentity();
        } catch (e) {
          debugPrint('Error clearing active identity: $e');
        }
      }
    }

    final bool supportImage = needsImageSupport;

    // First, ensure the model is registered with flutter_gemma
    final fileName = ModelHuggingFaceURLs.fileNameFor(model);
    final existsOnDisk =
        await ModelManager.instance.isInstalledOnDisk(fileName);

    if (existsOnDisk) {
      _statusController.add(
        'Found ${model.displayName} on disk, registering...',
      );
      try {
        final modelPath = await _findModelPath(fileName);
        if (modelPath != null) {
          final fileSize = await File(modelPath).length();
          // Always call registerDiskModel to ensure model is properly registered
          await ModelManager.instance.registerDiskModel(
            filePath: modelPath,
            fileName: fileName,
            modelType: model.modelType,
            fileType: model.fileType,
            fileSizeBytes: fileSize,
          );

          // Now get the active model
          _statusController.add('Loading ${model.displayName}...');
          _activeModel = await FlutterGemma.getActiveModel(
            maxTokens: _tokenLimitFor(model),
            preferredBackend: PreferredBackend.gpu,
            supportImage: supportImage,
          ).timeout(const Duration(seconds: 30));
          _activeModelType = model;
          _activeModelSupportsImage = supportImage;
          _isInitialized = true;
          _statusController.add('${model.displayName} ready');
          _resetIdleTimer();
          return _activeModel!;
        }
      } catch (e) {
        debugPrint('Failed to load local model: $e');
        // File exists but failed to load — likely corrupted or incompatible.
        // Convert to a typed exception so the UI can show actionable info.
        if (e is ModelException) rethrow;
        throw ModelLoadException(
          'Failed to load ${model.displayName} from disk.',
          model: model,
          suggestion: 'The model file may be corrupted. '
              'Try re-downloading or pick a different file.',
          underlyingError: e,
        );
      }
    }

    // No active model or load failed — ask user before downloading
    final url = ModelHuggingFaceURLs.urlFor(model);
    final choice = await _showDownloadConsent(model: model, url: url);

    if (choice == DownloadConsent.pickFile) {
      // User wants to pick a file from device — throw a special exception
      // so the UI can handle the file picker flow.
      throw ModelNeedsFilePickException(model);
    }

    if (choice == DownloadConsent.cancel) {
      throw Exception('Download cancelled by user');
    }

    // choice == DownloadConsent.download — proceed with network install
    _statusController.add('Downloading ${model.displayName}...');
    try {
      final installed = await ModelManager.instance
          .installFromNetwork(
            url: url,
            modelType: model.modelType,
            fileType: model.fileType,
            onProgress: (progress) {
              _statusController.add(
                'Downloading ${model.displayName}: $progress%',
              );
            },
          )
          .timeout(const Duration(seconds: 300));

      if (installed == null) {
        throw ModelDownloadException(
          'Download of ${model.displayName} failed.',
          model: model,
          suggestion: 'Check your internet connection and try again.',
        );
      }

      // Now get the model after install
      _statusController.add('Loading ${model.displayName}...');
      _activeModel = await FlutterGemma.getActiveModel(
        maxTokens: _tokenLimitFor(model),
        preferredBackend: PreferredBackend.gpu,
        supportImage: supportImage,
      ).timeout(const Duration(seconds: 30));
      _activeModelType = model;
      _activeModelSupportsImage = supportImage;
      _isInitialized = true;
      _statusController.add('${model.displayName} ready');
      _resetIdleTimer();
      return _activeModel!;
    } on ModelException {
      rethrow;
    } on TimeoutException {
      throw ModelLoadException(
        '${model.displayName} loading timed out.',
        model: model,
        suggestion:
            'The model may be too large for your device, or the file may be corrupted. '
            'Try a smaller model or pick a file from your device.',
      );
    } catch (e) {
      _statusController.add('Failed to load ${model.displayName}: $e');
      // Classify the error
      final msg = e.toString().toLowerCase();
      if (msg.contains('storage') || msg.contains('no space')) {
        throw ModelStorageException(
          'Not enough storage for ${model.displayName}.',
          model: model,
          suggestion: 'Free up storage space and try again.',
          underlyingError: e,
        );
      }
      if (msg.contains('corrupt') ||
          msg.contains('invalid') ||
          msg.contains('unsupported')) {
        throw ModelLoadException(
          '${model.displayName} file is corrupted or incompatible.',
          model: model,
          suggestion: 'Re-download the model or pick a different file.',
          underlyingError: e,
        );
      }
      if (msg.contains('network') ||
          msg.contains('connection') ||
          msg.contains('socket')) {
        throw ModelDownloadException(
          'Network error downloading ${model.displayName}.',
          model: model,
          suggestion: 'Check your internet connection and try again.',
          underlyingError: e,
        );
      }
      throw ModelLoadException(
        'Failed to load ${model.displayName}.',
        model: model,
        suggestion: 'Try again or pick a file from your device.',
        underlyingError: e,
      );
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
  }) async* {
    final customModel = _preferredCustomModelOverride!;
    _statusController.add('Using custom model: ${customModel.displayName}');

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
      _statusController
          .add('Custom model file not found: ${customModel.fileName}');
      yield InferenceResult(
        text: 'Custom model file not found: ${customModel.fileName}\n\n'
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

      // Ensure model is registered with flutter_gemma
      await ModelManager.instance.registerDiskModel(
        filePath: modelPath,
        fileName: customModel.fileName,
        modelType: customModel.modelType,
        fileType: customModel.fileType,
        fileSizeBytes: fileSize,
      );

      // Load the model
      final needsImageSupport = customModel.hasVision && screenshot != null;
      _statusController.add('Loading ${customModel.displayName}...');
      inferenceModel = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.gpu,
        supportImage: needsImageSupport,
      ).timeout(const Duration(seconds: 60));

      _statusController.add('${customModel.displayName} ready');
    } on TimeoutException {
      yield InferenceResult(
        text: 'Timed out loading ${customModel.displayName}. '
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

    // Create chat with system prompt
    final buffer = StringBuffer(_getAssistantRole().systemPrompt);

    if (customModel.hasThinking) {
      buffer.write(
        ' When asked to think step by step, show your reasoning in <thinking> tags '
        'before your final answer.',
      );
    }

    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.write('\n\n$ragContext');
    }
    if (attachmentContext != null && attachmentContext.isNotEmpty) {
      buffer.write('\n\n--- Attached Data ---\n$attachmentContext');
    }

    final chat = await inferenceModel.createChat(
      systemInstruction: buffer.toString(),
      tools: tools,
      supportImage: customModel.hasVision,
    );

    // Add the user message
    final Message message;
    if (screenshot != null && customModel.hasVision) {
      message = Message.withImage(
        text: query,
        imageBytes: screenshot,
        isUser: true,
      );
    } else {
      message = Message.text(text: query, isUser: true);
    }

    await chat.addQuery(message);

    // Generate response
    String fullResponse = '';
    String? currentThinking;
    final textBuffer = StringBuffer();
    final inferenceStopwatch = Stopwatch()..start();

    bool hasPendingToolCalls = true;
    int toolRounds = 0;
    final List<Map<String, dynamic>> allToolCalls = [];

    while (hasPendingToolCalls && toolRounds < _maxToolRounds) {
      hasPendingToolCalls = false;
      toolRounds++;

      await for (final event in chat.generateChatResponseAsync()) {
        if (event is TextResponse) {
          final token = event.token;
          fullResponse += token;
          textBuffer.write(token);

          final parsedCalls = _tryParseFunctionCalls(textBuffer.toString());
          if (parsedCalls != null && parsedCalls.isNotEmpty) {
            final toolText = textBuffer.toString();
            final idx = fullResponse.lastIndexOf(toolText);
            if (idx >= 0) {
              fullResponse = fullResponse.substring(0, idx) +
                  fullResponse.substring(idx + toolText.length);
            }
            textBuffer.clear();

            for (final parsed in parsedCalls) {
              final toolName = parsed['name'] as String;
              final toolArgs = Map<String, dynamic>.from(parsed['args'] as Map);
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
            text: fullResponse,
            model: selector.primaryHeavy,
            isStreaming: true,
            thinking: currentThinking,
            toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
            inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
          );
        } else if (event is ThinkingResponse) {
          currentThinking = event.content;
          yield InferenceResult(
            text: fullResponse,
            model: selector.primaryHeavy,
            isStreaming: true,
            thinking: currentThinking,
            toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
            inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
          );
        }
      }

      if (hasPendingToolCalls) {
        final toolResultMessages = <Message>[];
        for (final tc in allToolCalls.where(
          (t) => t['status'] == 'completed' && t['result'] != null,
        )) {
          toolResultMessages.add(Message.text(
            text: jsonEncode(tc['result']),
            isUser: true,
          ));
        }
        if (toolResultMessages.isNotEmpty) {
          for (final msg in toolResultMessages) {
            await chat.addQuery(msg);
          }
        }
      }
    }

    inferenceStopwatch.stop();

    yield InferenceResult(
      text: fullResponse,
      model: selector.primaryHeavy,
      isStreaming: false,
      thinking: currentThinking,
      toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
      inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
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
    switch (model) {
      case NovaModel.smollm:
        return 512;
      case NovaModel.fastvlm:
        return 1024;
      case NovaModel.gemma3_1b:
        return 2048;
      case NovaModel.gemma4E2b:
        return 4096;
    }
  }

  static const _contextBudgetRatio = 0.6;
  static const _imageTokenEstimate = 500;

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
    if (message.hasImage) return _imageTokenEstimate;
    return (message.text.length / 4).round();
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
    }

    return selected;
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

    final ragContext = await MemoryService.retrieveContext(query);

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

    // Force primary model when requested - ensures heavy model is used for
    // reliability-critical scenarios like assistant mode
    if (forcePrimaryModel && _preferredCustomModelOverride == null) {
      model = selector.primaryHeavy;
      if (_debugMode) {
        _statusController
            .add('[DEBUG] Force Primary Model: ${model.displayName}');
      }
    } else if (_preferredCustomModelOverride != null) {
      // Custom model selected - use it directly (bypasses NovaModel selection)
      // Return early with custom model loading path
      yield* _processWithCustomModel(
        query: query,
        screenshot: screenshot,
        thinkingMode: thinkingMode,
        tools: tools,
        ragContext: ragContext,
        attachmentContext: attachmentContext,
        hasImageAttachments: hasImageAttachments,
      );
      return;
    } else if (_modelOverrideDirty && _preferredModelOverride != null) {
      model = _preferredModelOverride!;
      if ((screenshot != null || hasImageAttachments) && !model.hasVision) {
        model = selector.primaryHeavy.hasVision
            ? selector.primaryHeavy
            : selector.fastModel;
        _statusController.add(
          'Auto-switched to ${model.displayName} for image input',
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

    if (_modelOverrideDirty) {
      _modelOverrideDirty = false;
    }

    _activeChat ??= await inferenceModel.createChat(
      systemInstruction: _systemPromptFor(model, ragContext, attachmentContext),
      tools: tools,
      supportImage: model.hasVision,
    );

    await _truncateContext(_activeChat!, model);

    final Message message;
    if (screenshot != null) {
      message = Message.withImage(
        text: query,
        imageBytes: screenshot,
        isUser: true,
      );
    } else {
      message = Message.text(text: query, isUser: true);
    }

    await _activeChat!.addQuery(message);

    String fullResponse = '';
    String? currentThinking;
    final textBuffer = StringBuffer();
    final inferenceStopwatch = Stopwatch()..start();

    // Tool call loop: after executing a tool, re-generate so the model
    // can incorporate the tool result into its response.
    bool hasPendingToolCalls = true;
    int toolRounds = 0;
    final List<Map<String, dynamic>> allToolCalls = [];

    _isStreaming = true;
    _streamingCompleter = Completer<void>();

    try {
      while (hasPendingToolCalls && toolRounds < _maxToolRounds) {
        hasPendingToolCalls = false;
        toolRounds++;

        await for (final event in _activeChat!.generateChatResponseAsync()) {
          if (_streamingCompleter?.isCompleted ?? false) {
            debugPrint('Stream aborted by releaseIdleResources');
            break;
          }
          if (event is TextResponse) {
            final token = event.token;
            fullResponse += token;
            textBuffer.write(token);

            // Try to parse function calls from the accumulated buffer.
            final parsedCalls = _tryParseFunctionCalls(textBuffer.toString());
            if (parsedCalls != null && parsedCalls.isNotEmpty) {
              // Remove the raw JSON tool call text from fullResponse
              final toolText = textBuffer.toString();
              final idx = fullResponse.lastIndexOf(toolText);
              if (idx >= 0) {
                fullResponse = fullResponse.substring(0, idx) +
                    fullResponse.substring(idx + toolText.length);
              }
              textBuffer.clear();

              // Execute all tool calls found in this response
              for (final parsed in parsedCalls) {
                final toolName = parsed['name'] as String;
                final toolArgs =
                    Map<String, dynamic>.from(parsed['args'] as Map);
                _statusController.add('Executing $toolName...');

                allToolCalls.add({
                  'name': toolName,
                  'args': toolArgs,
                  'status': 'executing',
                });

                // Try MCP external tools first, then native tools
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

                // Update the last tool call with result
                if (allToolCalls.isNotEmpty) {
                  allToolCalls.last['status'] = 'done';
                  allToolCalls.last['result'] = toolResult;
                }

                await _sendToolResponse(toolName, toolResult);
                hasPendingToolCalls = true;
              }
            } else {
              yield InferenceResult(
                text: fullResponse,
                model: model,
                isStreaming: true,
                thinking: thinkingMode ? currentThinking : null,
                toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
              );
            }
          } else if (event is ThinkingResponse) {
            currentThinking = event.content;
            yield InferenceResult(
              text: fullResponse,
              model: model,
              isStreaming: true,
              thinking: currentThinking,
              toolCalls: allToolCalls.isNotEmpty ? allToolCalls : null,
            );
          } else if (event is FunctionCallResponse) {
            // Plugin-level function call detected
            _statusController.add('Executing ${event.name}...');

            allToolCalls.add({
              'name': event.name,
              'args': Map<String, dynamic>.from(event.args),
              'status': 'executing',
            });

            final toolResult = await ToolExecutorService.instance.executeTool(
              event.name,
              Map<String, dynamic>.from(event.args),
            );

            if (allToolCalls.isNotEmpty) {
              allToolCalls.last['status'] = 'done';
              allToolCalls.last['result'] = toolResult;
            }

            await _sendToolResponse(event.name, toolResult);
            hasPendingToolCalls = true;
          }
        }
      }
    } finally {
      _isStreaming = false;
      if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
        _streamingCompleter!.complete();
      }
      _streamingCompleter = null;
    }

    if (toolRounds >= _maxToolRounds && hasPendingToolCalls) {
      inferenceStopwatch.stop();
      yield InferenceResult(
        text: '$fullResponse\n\n[Tool call limit reached]',
        model: model,
        isStreaming: false,
        thinking: thinkingMode ? currentThinking : null,
        inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
      );
      await MemoryService.storeConversation(query, fullResponse);
      return;
    }

    inferenceStopwatch.stop();
    yield InferenceResult(
      text: fullResponse,
      model: model,
      isStreaming: false,
      thinking: thinkingMode ? currentThinking : null,
      inferenceTimeMs: inferenceStopwatch.elapsedMilliseconds,
    );

    await MemoryService.storeConversation(query, fullResponse);
  }

  /// Try to extract function calls from accumulated text.
  /// Returns a list of tool calls (may be multiple in a single response).
  /// Handles wrapped {"tool_calls":[...]}, flat {"name":"X","arguments":{...}},
  /// and string-typed arguments.
  List<Map<String, dynamic>>? _tryParseFunctionCalls(String text) {
    final parsed = _parseJsonSafely(text);
    if (parsed == null) return null;

    final results = <Map<String, dynamic>>[];

    // Try wrapped format: {"role":"assistant","tool_calls":[{...}]}
    if (parsed['tool_calls'] is List) {
      final calls = parsed['tool_calls'] as List;
      for (final call in calls) {
        if (call is Map) {
          final fn = call['function'] as Map?;
          if (fn != null && fn['name'] != null) {
            final args = _coerceArguments(fn['arguments']);
            results.add({'name': fn['name'], 'args': args});
          }
        }
      }
      if (results.isNotEmpty) return results;
    }

    // Try flat format: {"name":"X","arguments":{...}}
    if (parsed['name'] is String) {
      final args = _coerceArguments(parsed['arguments']);
      results.add({'name': parsed['name'], 'args': args});
      return results;
    }

    return results.isEmpty ? null : results;
  }

  /// Coerce arguments into a `Map<String, dynamic>`. Handles both Map and
  /// String-typed arguments (some models emit "arguments": "{}" as a string).
  Map<String, dynamic> _coerceArguments(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// Parse JSON safely from text that may contain leading/trailing noise.
  /// Returns null if the JSON is incomplete or invalid.
  Map<String, dynamic>? _parseJsonSafely(String text) {
    try {
      final trimmed = text.trim();
      if (!trimmed.startsWith('{')) return null;

      // Find the last complete JSON object
      final lastBrace = trimmed.lastIndexOf('}');
      if (lastBrace == -1) return null;
      final candidate = trimmed.substring(0, lastBrace + 1);
      if (!candidate.startsWith('{')) return null;

      // Remove any leading text (e.g. role prefix)
      final jsonStart = candidate.indexOf('{');
      if (jsonStart > 0) {
        final possible = candidate.substring(jsonStart);
        if (possible.startsWith('{')) {
          final decoded = jsonDecode(possible);
          if (decoded is Map<String, dynamic>) return decoded;
        }
      }
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
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
      final data = toolResult['data'];
      Uint8List? imageBytes;
      if (data is Uint8List) {
        imageBytes = data;
      } else if (data is List<int>) {
        imageBytes = Uint8List.fromList(data);
      }

      if (imageBytes != null &&
          imageBytes.isNotEmpty &&
          _activeModelSupportsImage) {
        final imageMessage = Message.withImage(
          text: '[Screenshot captured]',
          imageBytes: imageBytes,
          isUser: true,
        );
        await _activeChat!.addQuery(imageMessage);
      }

      final toolResponseMessage = Message.toolResponse(
        toolName: toolName,
        response: {
          'success': toolResult['success'] ?? false,
          if (imageBytes != null && _activeModelSupportsImage)
            'message': 'Screenshot captured and displayed above'
          else if (imageBytes != null)
            'message':
                'Screenshot captured, but the current model cannot process images'
          else
            'message':
                'No screenshot available — screen capture may not be active',
        },
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

  String _systemPromptFor(
    NovaModel model, [
    String? ragContext,
    String? attachmentContext,
  ]) {
    final identity = _getCachedIdentity();

    String base;
    if (identity != null && identity.name != 'Nova') {
      base = identity.buildSystemPrompt();
    } else {
      base = _getAssistantRole().systemPrompt;
    }

    final thinkingSuffix = model.hasThinking
        ? ' When asked to think step by step, show your reasoning in <thinking> tags '
            'before your final answer.'
        : '';

    final buffer = StringBuffer('$base$thinkingSuffix');

    if (ragContext != null && ragContext.isNotEmpty) {
      buffer.write('\n\n$ragContext');
    }

    if (attachmentContext != null && attachmentContext.isNotEmpty) {
      buffer.write('\n\n--- Attached Data ---\n$attachmentContext');
    }

    // Add data source context from MCP sources
    final enabledSources =
        McpService.instance.sources.where((s) => s.enabled).toList();
    if (enabledSources.isNotEmpty) {
      buffer.write('\n\n--- Connected Data Sources ---');
      for (final source in enabledSources) {
        buffer.write('\n- ${source.name}: ${source.description}');
      }
    }

    return buffer.toString();
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
    _activeModelSupportsImage = false;
    _preferredModelOverride = null;
    _modelOverrideDirty = false;
    await ChatHistoryService.clear();
    _historyClearedController.add(null);
  }

  Future<void> close() async {
    try {
      await _activeModel?.close();
    } catch (_) {}
    _activeModel = null;
    _activeChat = null;
    _activeModelSupportsImage = false;
    _isInitialized = false;
    await _historyClearedController.close();
  }

  Future<void> initializeDefaultModel() async {
    await _loadAssistantRole();
    await _loadPreferredModel();
    await _loadIdentity();
    try {
      await _getOrCreateModel(selector.fastModel);
    } catch (e) {
      debugPrint('Default model init failed (will retry on first use): $e');
    }
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
  }
}

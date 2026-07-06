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

  InferenceResult({
    required this.text,
    required this.model,
    this.isStreaming = false,
    this.thinking,
    this.toolCalls,
  });
}

class ModelOrchestrator {
  static final ModelOrchestrator instance = ModelOrchestrator._();
  ModelOrchestrator._();

  final ModelSelector selector = ModelSelector(
    primaryHeavy: NovaModel.gemma4E2b,
    fastModel: NovaModel.smollm,
  );

  InferenceModel? _activeModel;
  InferenceChat? _activeChat;
  NovaModel? _activeModelType;
  bool _activeModelSupportsImage = false;
  NovaModel? _preferredModelOverride;
  bool _modelOverrideDirty = false;
  bool _isInitialized = false;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _historyClearedController = StreamController<void>.broadcast();
  Stream<void> get historyClearedStream => _historyClearedController.stream;

  bool get isInitialized => _isInitialized;

  NovaModel? get preferredModelType => _preferredModelOverride;

  set preferredModelType(NovaModel? model) {
    if (_preferredModelOverride == model) return;
    _preferredModelOverride = model;
    _modelOverrideDirty = true;
    _activeChat = null;
    if (_activeModel != null &&
        (_activeModelType == null ||
            model == null ||
            model != _activeModelType)) {
      _activeModel!.close().catchError((_) {});
      _activeModel = null;
    }
  }

  void clearModelOverride() {
    _preferredModelOverride = null;
    _modelOverrideDirty = false;
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

    for (final model in NovaModel.values) {
      final fileName = ModelHuggingFaceURLs.fileNameFor(model);

      // Already tracked?
      if (ModelManager.instance.isModelInstalled(fileName)) continue;

      // Check disk directly
      File? foundFile;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        foundFile = file;
      } else {
        final modelsDir = Directory('${dir.path}/models');
        if (await modelsDir.exists()) {
          await for (final entity in modelsDir.list()) {
            if (entity is File) {
              final baseName = p.basename(entity.path);
              if (baseName.contains(
                fileName.replaceAll('.litertlm', '').replaceAll('.task', ''),
              )) {
                foundFile = entity;
                break;
              }
            }
          }
        }
      }

      if (foundFile != null) {
        await ModelManager.instance.registerDiskModel(
          filePath: foundFile.path,
          fileName: fileName,
          modelType: model.modelType,
          fileType: model.fileType,
          fileSizeBytes: await foundFile.length(),
        );
      }
    }
  }

  Future<InferenceModel> _getOrCreateModel(
    NovaModel model, [
    Uint8List? screenshot,
  ]) async {
    final needsImageSupport = model.hasVision && screenshot != null;

    // Return cached model if same type AND image support setting matches
    if (_activeModel != null &&
        _activeModelType == model &&
        _activeModelSupportsImage == needsImageSupport) {
      return _activeModel!;
    }

    // --- Switching models ---
    // Close previous model AND clear flutter_gemma's active identity so
    // getActiveModel() won't return the stale model from a prior session.
    final switchingModel =
        _activeModelType != null && _activeModelType != model;
    if (switchingModel || (_activeModel != null && _activeModelType != model)) {
      try {
        await _activeModel!.close();
      } catch (e) {
        debugPrint('Error closing previous model: $e');
      }
      _activeModel = null;
      _activeChat = null;
      // Reset flutter_gemma's active model so it doesn't return the old one
      try {
        await FlutterGemma.clearActiveInferenceIdentity();
      } catch (e) {
        debugPrint('Error clearing active identity: $e');
      }
    }

    final bool supportImage = needsImageSupport;

    // If flutter_gemma has an active model (e.g., same model type restored on
    // startup), try to use it directly.
    if (FlutterGemma.hasActiveModel() && !switchingModel) {
      try {
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
        return _activeModel!;
      } catch (e) {
        debugPrint('getActiveModel failed: $e');
        _statusController.add('Model load failed, trying local...');
        _activeModel = null;
        // Don't swallow — if this is a clear "no model" error, convert it
        if (e is StateError && e.message.contains('No active')) {
          throw ModelNotFoundException(
            '${model.displayName} is not installed.',
            model: model,
            suggestion: 'Download it or pick a file from your device.',
            underlyingError: e,
          );
        }
      }
    }

    // Check if model exists on disk but wasn't restored (e.g., after app restart)
    final fileName = ModelHuggingFaceURLs.fileNameFor(model);
    final existsOnDisk = await ModelManager.instance.isInstalledOnDisk(
      fileName,
    );

    // If exists on disk, register it without downloading
    if (existsOnDisk) {
      _statusController.add(
        'Found ${model.displayName} on disk, registering...',
      );
      try {
        final modelPath = await _findModelPath(fileName);
        if (modelPath != null) {
          final fileSize = await File(modelPath).length();
          await ModelManager.instance.registerDiskModel(
            filePath: modelPath,
            fileName: fileName,
            modelType: model.modelType,
            fileType: model.fileType,
            fileSizeBytes: fileSize,
          );
          _activeModel = await FlutterGemma.getActiveModel(
            maxTokens: _tokenLimitFor(model),
            preferredBackend: PreferredBackend.gpu,
            supportImage: supportImage,
          ).timeout(const Duration(seconds: 30));
          _activeModelType = model;
          _activeModelSupportsImage = supportImage;
          _isInitialized = true;
          _statusController.add('${model.displayName} ready');
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
          suggestion:
              'The model file may be corrupted. '
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
    if (message.text == null) return 0;
    return (message.text!.length / 4).round();
  }

  NovaModel _selectModel({
    required String query,
    Uint8List? screenshot,
    bool thinkingMode = false,
  }) {
    final selected = selector.selectForQuery(
      query: query,
      hasVisionContext: screenshot != null,
      requestedThinking: thinkingMode,
    );

    if (screenshot != null && !selected.hasVision) {
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
  }) async* {
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
    if (_modelOverrideDirty && _preferredModelOverride != null) {
      model = _preferredModelOverride!;
      if (screenshot != null && !model.hasVision) {
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
        thinkingMode: thinkingMode,
      );
    }

    if (_modelOverrideDirty) {
      _modelOverrideDirty = false;
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

    // Tool call loop: after executing a tool, re-generate so the model
    // can incorporate the tool result into its response.
    bool hasPendingToolCalls = true;
    int toolRounds = 0;
    final List<Map<String, dynamic>> allToolCalls = [];
    while (hasPendingToolCalls && toolRounds < _maxToolRounds) {
      hasPendingToolCalls = false;
      toolRounds++;

      await for (final event in _activeChat!.generateChatResponseAsync()) {
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
              fullResponse =
                  fullResponse.substring(0, idx) +
                  fullResponse.substring(idx + toolText.length);
            }
            textBuffer.clear();

            // Execute all tool calls found in this response
            for (final parsed in parsedCalls) {
              final toolName = parsed['name'] as String;
              final toolArgs = Map<String, dynamic>.from(parsed['args'] as Map);
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

    if (toolRounds >= _maxToolRounds && hasPendingToolCalls) {
      yield InferenceResult(
        text: '$fullResponse\n\n[Tool call limit reached]',
        model: model,
        isStreaming: false,
        thinking: thinkingMode ? currentThinking : null,
      );
      await MemoryService.storeConversation(query, fullResponse);
      return;
    }

    yield InferenceResult(
      text: fullResponse,
      model: model,
      isStreaming: false,
      thinking: thinkingMode ? currentThinking : null,
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
    if (toolName == 'take_screenshot') {
      final data = toolResult['data'];
      Uint8List? imageBytes;
      if (data is Uint8List) {
        imageBytes = data;
      } else if (data is List<int>) {
        imageBytes = Uint8List.fromList(data);
      }

      if (imageBytes != null && imageBytes.isNotEmpty) {
        // Inject screenshot as an image message so the model can see it
        final imageMessage = Message.withImage(
          text: '[Screenshot captured]',
          imageBytes: imageBytes,
          isUser: true,
        );
        await _activeChat!.addQuery(imageMessage);
      }

      // Send text-only confirmation as the tool response
      final toolResponseMessage = Message.toolResponse(
        toolName: toolName,
        response: {
          'success': toolResult['success'] ?? false,
          'message': imageBytes != null
              ? 'Screenshot captured and displayed above'
              : 'No screenshot available — screen capture may not be active',
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
    final enabledSources = McpService.instance.sources
        .where((s) => s.enabled)
        .toList();
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
    _activeChat = null;
    _activeModelSupportsImage = false;
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

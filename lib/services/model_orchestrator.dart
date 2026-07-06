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
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/platform/tool_executor_service.dart';

class InferenceResult {
  final String text;
  final NovaModel model;
  final bool isStreaming;
  final String? thinking;

  InferenceResult({
    required this.text,
    required this.model,
    this.isStreaming = false,
    this.thinking,
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

    // Close previous model if switching type or image support requirement
    if (_activeModel != null) {
      try {
        await _activeModel!.close();
      } catch (e) {
        debugPrint('Error closing previous model: $e');
      }
      _activeModel = null;
      _activeChat = null;
    }

    final bool supportImage = needsImageSupport;

    // Try to get the active model with timeout
    if (FlutterGemma.hasActiveModel()) {
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
        // Find the actual file path and re-register with flutter_gemma.
        // Use registerDiskModel (not installFromFile) to avoid redundant file
        // copy and ensure canonical filename is used.
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
        // Fall through to download
      }
    }

    // No active model or load failed — try to install from network
    _statusController.add('Downloading ${model.displayName}...');
    try {
      final url = ModelHuggingFaceURLs.urlFor(model);
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
        throw Exception('Model installation returned null');
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
    } catch (e) {
      _statusController.add('Failed to load ${model.displayName}: $e');
      rethrow;
    }
  }

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
    } catch (e) {
      _statusController.add('Error: $e');
      yield InferenceResult(
        text: 'Failed to load model: $e\n\nPlease check Settings > AI Models.',
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
    while (hasPendingToolCalls && toolRounds < _maxToolRounds) {
      hasPendingToolCalls = false;
      toolRounds++;

      await for (final event in _activeChat!.generateChatResponseAsync()) {
        if (event is TextResponse) {
          final token = event.token;
          fullResponse += token;
          textBuffer.write(token);

          // Try to parse function calls from the accumulated buffer.
          // Returns null if JSON is incomplete/truncated, or a non-empty
          // list if one or more complete tool calls were found.
          final parsedCalls = _tryParseFunctionCalls(textBuffer.toString());
          if (parsedCalls != null && parsedCalls.isNotEmpty) {
            // Remove the raw JSON tool call text from fullResponse so it
            // doesn't leak into the final user-visible response.
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
              _statusController.add('Executing ${parsed['name']}...');

              final toolResult = await ToolExecutorService.instance.executeTool(
                parsed['name'] as String,
                Map<String, dynamic>.from(parsed['args'] as Map),
              );

              final toolResponseMessage = Message.toolResponse(
                toolName: parsed['name'] as String,
                response: Map<String, dynamic>.from(toolResult),
              );

              await _activeChat!.addQuery(toolResponseMessage);
              hasPendingToolCalls = true;
            }
            // Don't yield here — wait for the next generation pass
          } else {
            yield InferenceResult(
              text: fullResponse,
              model: model,
              isStreaming: true,
              thinking: thinkingMode ? currentThinking : null,
            );
          }
        } else if (event is ThinkingResponse) {
          currentThinking = event.content;
          yield InferenceResult(
            text: fullResponse,
            model: model,
            isStreaming: true,
            thinking: currentThinking,
          );
        } else if (event is FunctionCallResponse) {
          // Plugin-level function call detected
          _statusController.add('Executing ${event.name}...');

          final toolResult = await ToolExecutorService.instance.executeTool(
            event.name,
            Map<String, dynamic>.from(event.args),
          );

          final toolResponseMessage = Message.toolResponse(
            toolName: event.name,
            response: Map<String, dynamic>.from(toolResult),
          );

          await _activeChat!.addQuery(toolResponseMessage);
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

  /// Coerce arguments into a Map<String, dynamic>. Handles both Map and
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

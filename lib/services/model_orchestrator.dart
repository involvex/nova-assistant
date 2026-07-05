import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';
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
  bool _isInitialized = false;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  bool get isInitialized => _isInitialized;

  Future<void> prefetchModels() async {
    _statusController.add('Checking models...');
    try {
      if (!ModelManager.instance.isModelInstalled(
        ModelHuggingFaceURLs.fileNameFor(NovaModel.smollm),
      )) {
        await ModelManager.instance.installFromNetwork(
          url: ModelHuggingFaceURLs.smollm,
          modelType: NovaModel.smollm.modelType,
        );
      }
      if (!ModelManager.instance.isModelInstalled(
        ModelHuggingFaceURLs.fileNameFor(NovaModel.gemma4E2b),
      )) {
        await ModelManager.instance.installFromNetwork(
          url: ModelHuggingFaceURLs.gemma4E2b,
          modelType: NovaModel.gemma4E2b.modelType,
        );
      }
      _statusController.add('Models ready');
    } catch (e) {
      _statusController.add('Model download failed: $e');
    }
  }

  Future<InferenceModel> _getOrCreateModel(NovaModel model) async {
    // Return cached model if same type
    if (_activeModel != null && _activeModelType == model) {
      return _activeModel!;
    }

    // Close previous model if switching
    if (_activeModel != null && _activeModelType != model) {
      try {
        await _activeModel!.close();
      } catch (e) {
        debugPrint('Error closing previous model: $e');
      }
      _activeModel = null;
      _activeChat = null;
    }

    // Try to get the active model with timeout
    if (FlutterGemma.hasActiveModel()) {
      try {
        _statusController.add('Loading ${model.displayName}...');
        _activeModel = await FlutterGemma.getActiveModel(
          maxTokens: _tokenLimitFor(model),
          preferredBackend: PreferredBackend.gpu,
        ).timeout(const Duration(seconds: 30));
        _activeModelType = model;
        _isInitialized = true;
        _statusController.add('${model.displayName} ready');
        return _activeModel!;
      } catch (e) {
        debugPrint('getActiveModel failed: $e');
        _statusController.add('Model load failed, trying reinstall...');
        _activeModel = null;
      }
    }

    // No active model or load failed — try to install
    _statusController.add('Downloading ${model.displayName}...');
    try {
      final url = ModelHuggingFaceURLs.urlFor(model);
      final installed = await ModelManager.instance
          .installFromNetwork(
            url: url,
            modelType: model.modelType,
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
      ).timeout(const Duration(seconds: 30));
      _activeModelType = model;
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
    return selector.selectForQuery(
      query: query,
      hasVisionContext: screenshot != null,
      requestedThinking: thinkingMode,
    );
  }

  Stream<InferenceResult> processMessage({
    required String query,
    Uint8List? screenshot,
    bool thinkingMode = false,
    List<Tool> tools = const [],
  }) async* {
    final model = _selectModel(
      query: query,
      screenshot: screenshot,
      thinkingMode: thinkingMode,
    );

    _statusController.add('Using ${model.displayName}');

    InferenceModel inferenceModel;
    try {
      inferenceModel = await _getOrCreateModel(model);
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
      systemInstruction: _systemPromptFor(model),
      tools: tools,
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

    await for (final event in _activeChat!.generateChatResponseAsync()) {
      if (event is TextResponse) {
        fullResponse += event.token;
        yield InferenceResult(
          text: fullResponse,
          model: model,
          isStreaming: true,
          thinking: thinkingMode ? currentThinking : null,
        );
      } else if (event is ThinkingResponse) {
        currentThinking = event.content;
        yield InferenceResult(
          text: fullResponse,
          model: model,
          isStreaming: true,
          thinking: currentThinking,
        );
      } else if (event is FunctionCallResponse) {
        final toolResult = await ToolExecutorService.instance.executeTool(
          event.name,
          Map<String, dynamic>.from(event.args),
        );

        final toolResponseMessage = Message.toolResponse(
          toolName: event.name,
          response: Map<String, dynamic>.from(toolResult),
        );

        await _activeChat!.addQuery(toolResponseMessage);
      }
    }

    yield InferenceResult(
      text: fullResponse,
      model: model,
      isStreaming: false,
      thinking: thinkingMode ? currentThinking : null,
    );
  }

  String _systemPromptFor(NovaModel model) {
    final base =
        'You are Nova, a helpful on-device AI assistant powered by Gemma. '
        'You run entirely on the device — no data is sent to servers. '
        'Be concise, helpful, and friendly. ';

    if (model.hasThinking) {
      return '$base When asked to think step by step, show your reasoning in <thinking> tags '
          'before your final answer.';
    }
    return base;
  }

  Future<void> clearHistory() async {
    _activeChat = null;
  }

  Future<void> close() async {
    try {
      await _activeModel?.close();
    } catch (_) {}
    _activeModel = null;
    _activeChat = null;
    _isInitialized = false;
  }

  Future<void> initializeDefaultModel() async {
    try {
      await _getOrCreateModel(selector.fastModel);
    } catch (e) {
      debugPrint('Default model init failed (will retry on first use): $e');
    }
  }
}

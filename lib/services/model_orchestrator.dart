import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
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
    // Pre-download all three models in background
    _statusController.add('Downloading models...');

    try {
      // Download in parallel — all run in background
      await Future.wait([
        _downloadModel(NovaModel.smollm),
        _downloadModel(NovaModel.gemma4E2b),
      ], eagerError: false);
      _statusController.add('Models ready');
    } catch (e) {
      _statusController.add('Model download failed: $e');
    }
  }

  Future<void> _downloadModel(NovaModel model) async {
    final url = ModelHuggingFaceURLs.urlFor(model);
    _statusController.add('Downloading ${model.displayName}...');
    try {
      await FlutterGemma.installModel(
        modelType: model.modelType,
      ).fromNetwork(url).install();
      print('Model downloaded: ${model.displayName}');
    } catch (e) {
      print('Failed to download ${model.displayName}: $e');
    }
  }

  Future<InferenceModel> _getOrCreateModel(NovaModel model) async {
    if (_activeModel != null && _activeModelType == model) {
      return _activeModel!;
    }

    // Close previous model if switching
    if (_activeModel != null && _activeModelType != model) {
      await _activeModel!.close();
      _activeModel = null;
      _activeChat = null;
    }

    // Ensure model is installed before calling getActiveModel()
    if (!FlutterGemma.hasActiveModel()) {
      _statusController.add('Installing ${model.displayName}...');
      await _downloadModel(model);
    }

    _statusController.add('Loading ${model.displayName}...');
    _activeModel = await FlutterGemma.getActiveModel(
      maxTokens: _tokenLimitFor(model),
      preferredBackend: PreferredBackend.gpu,
    );
    _activeModelType = model;
    _isInitialized = true;
    _statusController.add('${model.displayName} ready');

    return _activeModel!;
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

    final inferenceModel = await _getOrCreateModel(model);

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

    // Final non-streaming result
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
    // Keep model loaded, just clear conversation
  }

  Future<void> close() async {
    await _activeModel?.close();
    _activeModel = null;
    _activeChat = null;
    _isInitialized = false;
  }
}

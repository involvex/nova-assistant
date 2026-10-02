// ignore_for_file: prefer_initializing_formals
import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/providers/provider_capabilities.dart';
import 'package:nova_assistant/services/remote_inference_client.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';

/// Generic OpenAI-compatible cloud provider.
///
/// Covers OpenAI, OpenRouter, Groq, Opencode Zen and Kilo Gateway — all
/// expose `/v1/chat/completions` (SSE) + `/v1/models`. Copilot is
/// intentionally skipped per decision (OAuth device-flow, no stable API).
class OpenAiCompatibleProvider implements AIProvider {
  OpenAiCompatibleProvider({
    required this.providerId,
    required RemoteInferenceConfig config,
    RemoteInferenceClient? client,
  }) : _config = config,
       _client = client ?? RemoteInferenceClient();

  final String providerId;
  RemoteInferenceConfig _config;
  final RemoteInferenceClient _client;

  @override
  String get id => providerId;

  @override
  bool get isLocal => false;

  @override
  Set<ProviderCapability> get capabilities {
    return <ProviderCapability>{
      ProviderCapability.chat,
      ProviderCapability.streaming,
      ProviderCapability.vision,
      ProviderCapability.toolCalling,
    };
  }

  @override
  Future<void> ensureReady() async {
    final bool ok = await _client.testConnection(_config);
    if (!ok) {
      throw StateError(
        'Provider $providerId unreachable at ${_config.baseUrl}',
      );
    }
  }

  /// Re-points the provider without re-registering (settings edits at
  /// runtime). Called by `NovaBootstrap.refreshProviderConfigs`.
  void updateConfig(RemoteInferenceConfig config) {
    _config = config;
  }

  List<Map<String, String>> _toMessages(AIRequest request) {
    final List<Map<String, String>> messages = <Map<String, String>>[];
    if (request.systemPrompt != null && request.systemPrompt!.isNotEmpty) {
      messages.add(<String, String>{
        'role': 'system',
        'content': request.systemPrompt!,
      });
    }
    for (final ChatTurn turn in request.messages) {
      messages.add(turn.toOpenAiMap());
    }

    return messages;
  }

  RemoteInferenceConfig _configFor(AIRequest request) {
    if (request.modelId != null && request.modelId!.isNotEmpty) {
      return _config.copyWith(modelId: request.modelId);
    }

    return _config;
  }

  @override
  Stream<String> chatStream(AIRequest request) {
    final RemoteInferenceConfig config = _configFor(request);

    return _client.streamChat(
      config: config,
      messages: _toMessages(request),
      temperature: request.temperature,
    );
  }

  @override
  Future<String> chat(AIRequest request) async {
    final StringBuffer buffer = StringBuffer();
    await for (final String chunk in chatStream(request)) {
      buffer.write(chunk);
    }

    return buffer.toString();
  }

  @override
  Future<List<double>> embed(String text) {
    throw UnsupportedError('$providerId embeddings not wired yet');
  }
}

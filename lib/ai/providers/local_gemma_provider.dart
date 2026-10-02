import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/providers/provider_capabilities.dart';
import 'package:nova_assistant/models/model_info.dart';

/// Adapter around the existing on-device Gemma engine (`flutter_gemma`).
///
/// Wraps the exact semantics the [ModelOrchestrator] relies on today:
/// single active model, `supportImage` for vision models, native tool-call
/// retry handled by the caller. No behavior change in Phase 1.
class LocalGemmaProvider implements AIProvider {
  LocalGemmaProvider({this.model = NovaModel.gemma4E2b});

  final NovaModel model;

  @override
  String get id => 'local-gemma';

  @override
  bool get isLocal => true;

  @override
  Set<ProviderCapability> get capabilities {
    return <ProviderCapability>{
      ProviderCapability.chat,
      ProviderCapability.streaming,
      if (model.hasVision) ProviderCapability.vision,
      if (model.supportsFunctionCalling) ProviderCapability.toolCalling,
    };
  }

  @override
  Future<void> ensureReady() async {
    // Engine is lazily loaded by ModelOrchestrator today; nothing to do here
    // until Phase 6 moves model lifecycle into the provider.
    return;
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
    throw UnsupportedError('local-gemma does not support embeddings');
  }

  @override
  Stream<String> chatStream(AIRequest request) async* {
    final InferenceModel engine = await FlutterGemma.getActiveModel(
      supportImage: model.hasVision && request.hasImage,
    );
    final InferenceChat chat = await engine.createChat(
      systemInstruction:
          request.systemPrompt ?? 'You are Nova, a helpful assistant.',
      supportImage: model.hasVision && request.hasImage,
      supportsFunctionCalls: false,
      tools: const <Tool>[],
    );
    try {
      final ChatTurn last = request.messages.last;
      await chat.addQuery(Message.text(text: last.text, isUser: true));
      await for (final Object event in chat.generateChatResponseAsync()) {
        if (event is TextResponse) {
          yield event.token;
        }
      }
    } finally {
      try {
        await chat.close();
      } catch (e) {
        debugPrint('LocalGemmaProvider: chat close failed: $e');
      }
    }
  }
}

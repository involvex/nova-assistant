import 'dart:typed_data';

import 'package:nova_assistant/ai/providers/provider_capabilities.dart';

/// Single chat turn, provider-agnostic.
///
/// Deliberately decoupled from [ChatMessage] and `flutter_edge_ai` so cloud
/// providers (OpenAI-compatible, OpenRouter, Groq, Opencode Zen,
/// Kilo Gateway) can reuse the same DTO.
class ChatTurn {
  const ChatTurn({required this.role, required this.text, this.imageBytes});

  final String role;
  final String text;
  final Uint8List? imageBytes;

  Map<String, String> toOpenAiMap() {
    return <String, String>{'role': role, 'content': text};
  }
}

/// Reference to a tool by name. Full `abstract Tool` lands in Phase 3;
/// Phase 1 only passes names through so the orchestrator keeps working.
class ToolRef {
  const ToolRef(this.name);

  final String name;
}

/// Provider-agnostic inference request.
class AIRequest {
  const AIRequest({
    required this.messages,
    this.systemPrompt,
    this.tools = const <ToolRef>[],
    this.temperature = 0.7,
    this.hasImage = false,
    this.modelId,
  });

  final List<ChatTurn> messages;
  final String? systemPrompt;
  final List<ToolRef> tools;
  final double temperature;
  final bool hasImage;

  /// Explicit model for this turn (smart-routing preset). Null means
  /// the provider default (the model configured in settings).
  final String? modelId;
}

/// Unified provider interface. Nova Core may only depend on this,
/// never on `flutter_edge_ai`, `HttpClient` or `MethodChannel` directly.
abstract class AIProvider {
  String get id;

  Set<ProviderCapability> get capabilities;

  bool get isLocal;

  Future<void> ensureReady();

  Future<String> chat(AIRequest request);

  Stream<String> chatStream(AIRequest request);

  Future<List<double>> embed(String text);
}

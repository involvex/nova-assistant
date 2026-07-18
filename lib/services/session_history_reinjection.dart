import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/chat_message.dart';

/// Converts persisted UI chat turns into LiteRT replay messages.
class SessionHistoryReinjection {
  const SessionHistoryReinjection._();

  static const imageTokenEstimate = 500;

  static int estimateTokens(Message message) {
    if (message.hasImage) return imageTokenEstimate;

    return (message.text.length / 4).round();
  }

  static int estimateChatMessageTokens(ChatMessage message) {
    if (message.imageData != null && message.imageData!.isNotEmpty) {
      return imageTokenEstimate;
    }

    return (message.text.length / 4).round();
  }

  /// Newest-first fit into [maxTokens] (hard cap), returned oldest→newest.
  ///
  /// Messages that would push the running total over [maxTokens] are skipped.
  /// A single oversized newest message is omitted rather than exceeding the
  /// budget (callers that need it can raise [maxTokens] or compact first).
  static List<Message> buildReplayMessages(
    List<ChatMessage> uiMessages, {
    required int maxTokens,
  }) {
    final usable = uiMessages.where(_isReplayable).toList();

    final selected = <ChatMessage>[];
    var tokens = 0;
    for (var i = usable.length - 1; i >= 0; i--) {
      final msg = usable[i];
      final cost = estimateChatMessageTokens(msg);
      if (tokens + cost > maxTokens) break;
      selected.add(msg);
      tokens += cost;
    }

    return selected.reversed.map(_toMessage).toList();
  }

  static bool _isReplayable(ChatMessage m) {
    if (m.isStreaming || m.isError) return false;
    if (m.text.trim().isNotEmpty) return true;
    if (m.imageData != null && m.imageData!.isNotEmpty) return true;

    return false;
  }

  static Message _toMessage(ChatMessage m) {
    final bytes = m.imageData;
    if (bytes != null && bytes.isNotEmpty) {
      return Message.withImage(
        text: m.text,
        imageBytes: bytes,
        isUser: m.isUser,
      );
    }

    return Message(text: m.text, isUser: m.isUser);
  }
}

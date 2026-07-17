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

  /// Newest-first fit into [maxTokens], returned oldest→newest for replay.
  static List<Message> buildReplayMessages(
    List<ChatMessage> uiMessages, {
    required int maxTokens,
  }) {
    final usable = uiMessages
        .where((m) => !m.isStreaming && !m.isError && m.text.trim().isNotEmpty)
        .toList();

    final selected = <ChatMessage>[];
    var tokens = 0;
    for (var i = usable.length - 1; i >= 0; i--) {
      final msg = usable[i];
      final cost = estimateChatMessageTokens(msg);
      if (selected.isNotEmpty && tokens + cost > maxTokens) break;
      selected.add(msg);
      tokens += cost;
    }

    return selected.reversed.map(_toMessage).toList();
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

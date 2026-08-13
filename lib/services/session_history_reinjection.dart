import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/utils/message_limits.dart';
import 'package:nova_assistant/utils/tool_call_parser.dart';

/// Converts persisted UI chat turns into LiteRT replay messages.
class SessionHistoryReinjection {
  const SessionHistoryReinjection._();

  static const imageTokenEstimate = 500;

  /// Max complete turn pairs kept for tiny-context models (SmolLM).
  static const maxPairsForTightBudget = 3;

  static int estimateTokens(Message message) {
    if (message.hasImage) return imageTokenEstimate;

    return (message.text.length / 4).round();
  }

  /// Per-model real-token estimate for a persisted chat turn.
  ///
  /// Defaults to Gemma 4's ratio (the default inference model) when [model]
  /// is null. Falls back to the legacy chars/4 estimate when the message has
  /// an attached image (image tokens are dominated by the vision pipeline,
  /// not by the tokenizer).
  static int estimateChatMessageTokens(
    ChatMessage message, {
    NovaModel? model,
  }) {
    if (message.imageData != null && message.imageData!.isNotEmpty) {
      return imageTokenEstimate;
    }

    return MessageLimits.estimateRealTokens(message.text, model: model);
  }

  /// Newest-first fit into [maxTokens] (hard cap), returned oldest→newest.
  ///
  /// Skips cancelled / stop-only / error / streaming turns. Trims in
  /// user↔assistant pairs so the oldest kept message is never a lone
  /// assistant reply. Sanitizes ChatML/tool markup before conversion.
  ///
  /// When [model] is provided the per-model real-token ratio table is used
  /// for budgeting. Defaults to Gemma 4 (the default inference model) to
  /// keep callers that don't know the model name out of trouble.
  static List<Message> buildReplayMessages(
    List<ChatMessage> uiMessages, {
    required int maxTokens,
    NovaModel? model,
  }) {
    final usable = uiMessages.where(_isReplayable).toList();
    if (usable.isEmpty) return const [];

    final supportsVision = model?.hasVision ?? false;

    // For very small budgets (SmolLM ~394), prefer last N complete pairs.
    final tight = maxTokens <= 500;
    final candidates = tight ? _lastCompletePairs(usable) : usable;

    final selected = <ChatMessage>[];
    var tokens = 0;
    for (var i = candidates.length - 1; i >= 0; i--) {
      final msg = candidates[i];
      final cost = estimateChatMessageTokens(msg, model: model);
      if (tokens + cost > maxTokens) break;
      selected.add(msg);
      tokens += cost;
    }

    final ordered = selected.reversed.toList();
    final paired = _dropLeadingOrphanAssistant(ordered);

    return paired.map((m) => _toMessage(m, supportsVision)).toList();
  }

  static bool _isReplayable(ChatMessage m) {
    if (m.isStreaming || m.isError || m.wasCancelled) return false;
    final trimmed = m.text.trim();
    if (_isStopOnlyText(trimmed)) return false;
    if (trimmed.isNotEmpty) return true;
    if (m.imageData != null && m.imageData!.isNotEmpty) return true;

    return false;
  }

  static bool _isStopOnlyText(String text) {
    if (text.isEmpty) return false;
    final cleaned = text
        .replaceAll('⏹ Stopped', '')
        .replaceAll('Stopped', '')
        .trim();

    return cleaned.isEmpty && text.contains('⏹');
  }

  /// Keep only the last [maxPairsForTightBudget] complete user+assistant pairs
  /// (plus a trailing unpaired user turn if present).
  static List<ChatMessage> _lastCompletePairs(List<ChatMessage> usable) {
    final pairs = <List<ChatMessage>>[];
    var i = 0;
    while (i < usable.length) {
      final msg = usable[i];
      if (msg.isUser) {
        if (i + 1 < usable.length && !usable[i + 1].isUser) {
          pairs.add([msg, usable[i + 1]]);
          i += 2;
        } else {
          pairs.add([msg]);
          i += 1;
        }
      } else {
        // Orphan assistant — skip for tight budgets
        i += 1;
      }
    }

    if (pairs.length <= maxPairsForTightBudget) {
      return pairs.expand((p) => p).toList();
    }

    return pairs
        .sublist(pairs.length - maxPairsForTightBudget)
        .expand((p) => p)
        .toList();
  }

  /// If the oldest selected message is an assistant turn, drop it so replay
  /// always starts on a user message when possible.
  static List<ChatMessage> _dropLeadingOrphanAssistant(
    List<ChatMessage> ordered,
  ) {
    if (ordered.isEmpty) return ordered;
    if (!ordered.first.isUser) {
      return ordered.sublist(1);
    }

    return ordered;
  }

  static Message _toMessage(ChatMessage m, bool supportsVision) {
    final sanitized = ToolCallParser.stripMarkup(m.text);
    final bytes = m.imageData;
    if (supportsVision && bytes != null && bytes.isNotEmpty) {
      return Message.withImage(
        text: sanitized,
        imageBytes: bytes,
        isUser: m.isUser,
      );
    }

    return Message(text: sanitized, isUser: m.isUser);
  }
}

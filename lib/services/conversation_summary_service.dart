import 'package:flutter/foundation.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/services/chat_history_service.dart';

/// Result of an explicit context compact: extractive summary plus replay list.
class CompactResult {
  const CompactResult({
    required this.summary,
    required this.retainedMessages,
  });

  final String summary;
  final List<ChatMessage> retainedMessages;
}

/// Builds and stores rolling conversation summaries for RAG.
///
/// Uses extractive summarization (recent turns + key user intents) so we do
/// not load a second model mid-chat on low-RAM devices. The stored summary is
/// injected into [MemoryService.retrieveContext].
class ConversationSummaryService {
  static ConversationSummaryService? _instance;
  static ConversationSummaryService get instance =>
      _instance ??= ConversationSummaryService._();
  ConversationSummaryService._();

  static const _minMessagesForSummary = 6;
  static const _maxSummaryChars = 2000;

  /// Summary for the conversation currently open in the UI.
  String? activeSummary;

  /// Compact older turns into an extractive summary for inference replay.
  ///
  /// UI history is preserved — only [Conversation.summary] is persisted.
  /// [retainedMessages] is `[summary message] + last [keepRecent] usable turns`.
  Future<CompactResult> compactNow(
    Conversation conversation, {
    int keepRecent = 6,
  }) async {
    final summary = _buildExtractiveSummary(conversation.messages);
    final usable = conversation.messages
        .where((m) => !m.isStreaming && !m.isError && m.text.trim().isNotEmpty)
        .toList();
    final recent = usable.length > keepRecent
        ? usable.sublist(usable.length - keepRecent)
        : usable;

    final summaryMessage = ChatMessage(
      id: 'compact-${DateTime.now().millisecondsSinceEpoch}',
      text: '[Conversation summary]\n$summary',
      isUser: false,
      timestamp: DateTime.now(),
      modelName: 'compact',
    );

    final retained = [summaryMessage, ...recent];

    try {
      await ChatHistoryService.updateConversation(
        conversation.copyWith(summary: summary),
      );
      activeSummary = summary;
    } catch (e) {
      debugPrint('ConversationSummaryService.compactNow update error: $e');
    }

    return CompactResult(summary: summary, retainedMessages: retained);
  }

  /// Update summary when a conversation grows long enough.
  Future<String?> maybeUpdateSummary(Conversation conversation) async {
    if (conversation.messages.length < _minMessagesForSummary) {
      return conversation.summary;
    }

    final msgCount = conversation.messages.length;
    final existing = conversation.summary;
    if (existing != null && existing.isNotEmpty && msgCount % 4 != 0) {
      return existing;
    }

    try {
      final summary = _buildExtractiveSummary(conversation.messages);
      if (summary.isEmpty) return existing;

      final updated = conversation.copyWith(summary: summary);
      await ChatHistoryService.updateConversation(updated);
      activeSummary = summary;

      return summary;
    } catch (e) {
      debugPrint('ConversationSummaryService.maybeUpdateSummary error: $e');

      return conversation.summary;
    }
  }

  String _buildExtractiveSummary(List<ChatMessage> messages) {
    final usable = messages
        .where((m) => !m.isStreaming && !m.isError && m.text.trim().isNotEmpty)
        .toList();
    if (usable.isEmpty) return '';

    final userIntents = usable
        .where((m) => m.isUser)
        .map((m) => _clip(m.text, 120))
        .toList();
    final recent = usable.length > 8
        ? usable.sublist(usable.length - 8)
        : usable;

    final buf = StringBuffer();
    if (userIntents.isNotEmpty) {
      buf.writeln('User goals:');
      for (final intent in userIntents.take(5)) {
        buf.writeln('- $intent');
      }
      buf.writeln();
    }
    buf.writeln('Recent turns:');
    for (final m in recent) {
      final role = m.isUser ? 'User' : 'Assistant';
      buf.writeln('$role: ${_clip(m.text, 180)}');
    }

    var summary = buf.toString().trim();
    if (summary.length > _maxSummaryChars) {
      summary = summary.substring(0, _maxSummaryChars);
    }

    return summary;
  }

  String _clip(String text, int max) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= max) return cleaned;

    return '${cleaned.substring(0, max)}…';
  }
}

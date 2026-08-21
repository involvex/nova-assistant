import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/chat_bubble_theme.dart';
import 'package:nova_assistant/widgets/chat_bubble.dart';
import 'package:nova_assistant/widgets/suggestion_chip.dart';

typedef MessageRetryCallback = void Function(int messageIndex);
typedef MessageActionCallback = void Function(int messageIndex);
typedef MessageSpeakCallback = void Function(String text);
typedef MessageReactionRequestCallback = void Function(int messageIndex);
typedef MessageReactionChipCallback = void Function(
  int messageIndex,
  String emoji,
);
typedef MessageCopyCallback = void Function(ChatMessage message);
typedef MessageBranchCallback = void Function(int messageIndex);
typedef MessageScreenshotCallback = void Function(Uint8List data);

class MessageListView extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final ChatBubbleTheme chatTheme;
  final bool isGenerating;
  final bool hasConversationId;
  final MessageScreenshotCallback? onShowFullScreenshot;
  final MessageRetryCallback? onRetry;
  final VoidCallback? onOpenSettings;
  final MessageCopyCallback onCopy;
  final MessageReactionRequestCallback onReactionRequest;
  final MessageReactionChipCallback onReactionChipTap;
  final MessageActionCallback? onRegenerate;
  final MessageSpeakCallback? onSpeak;
  final MessageActionCallback? onEdit;
  final MessageBranchCallback? onBranchFromHere;
  final bool ttsEnabled;
  final List<({String label, String prompt})> starters;
  final ValueChanged<String> onFillComposer;
  final ValueChanged<String> onApplySuggestion;
  final String Function(DateTime?) formatTimestamp;

  const MessageListView({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.chatTheme,
    required this.isGenerating,
    required this.hasConversationId,
    this.onShowFullScreenshot,
    this.onRetry,
    this.onOpenSettings,
    required this.onCopy,
    required this.onReactionRequest,
    required this.onReactionChipTap,
    this.onRegenerate,
    this.onSpeak,
    this.onEdit,
    this.onBranchFromHere,
    required this.ttsEnabled,
    required this.starters,
    required this.onFillComposer,
    required this.onApplySuggestion,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return _buildEmptyState(context);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];

        return RepaintBoundary(
          child: ChatBubble(
            message: msg,
            theme: chatTheme,
            onScreenshotTap:
                msg.imageData != null && onShowFullScreenshot != null
                ? () => onShowFullScreenshot!(msg.imageData!)
                : null,
            onRetry: msg.isError && !msg.isUser && onRetry != null
                ? () => onRetry!(index)
                : null,
            onSettingsTap: msg.isError && !msg.isUser && onOpenSettings != null
                ? onOpenSettings
                : null,
            onCopy: () => onCopy(msg),
            onReactionRequest: () => onReactionRequest(index),
            onReactionChipTap: (emoji) => onReactionChipTap(index, emoji),
            onRegenerate:
                !msg.isUser &&
                    !msg.isError &&
                    !msg.isStreaming &&
                    onRegenerate != null
                ? () => onRegenerate!(index)
                : null,
            onSpeak:
                !msg.isUser &&
                    !msg.isError &&
                    !msg.isStreaming &&
                    ttsEnabled &&
                    onSpeak != null
                ? () => onSpeak!(msg.text)
                : null,
            onEdit: msg.isUser && !isGenerating && onEdit != null
                ? () => onEdit!(index)
                : null,
            onBranchFromHere:
                hasConversationId &&
                    !isGenerating &&
                    !msg.isStreaming &&
                    !msg.isError &&
                    onBranchFromHere != null
                ? () => onBranchFromHere!(index)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(22)),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Hi, I'm Nova",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your on-device AI assistant, powered by Gemma.\n'
                    'Tap the mic or type to start.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Try a prompt',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: starters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final starter = starters[index];
                        return SuggestionChip(
                          label: starter.label,
                          onTap: () => onFillComposer(starter.prompt),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      SuggestionChip(
                        label: "What's on my screen?",
                        onTap: () => onApplySuggestion("What's on my screen?"),
                      ),
                      SuggestionChip(
                        label: 'Set an alarm for 7:00 PM',
                        onTap: () =>
                            onApplySuggestion('Set an alarm for 7:00 PM'),
                      ),
                      SuggestionChip(
                        label: 'Open Settings',
                        onTap: () => onApplySuggestion('Open Settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

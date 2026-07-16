import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onScreenshotTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onCopy;
  final VoidCallback? onReactionRequest;
  final ValueChanged<String>? onReactionChipTap;

  const ChatBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onScreenshotTap,
    this.onSettingsTap,
    this.onCopy,
    this.onReactionRequest,
    this.onReactionChipTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Screenshot preview
            if (message.imageData != null)
              GestureDetector(
                onTap: onScreenshotTap,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(message.imageData!, fit: BoxFit.cover),
                  ),
                ),
              ),

            // Model badge
            if (!isUser && message.modelName != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: Color(0xFF6C63FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      message.modelName!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Tool call chips
            if (!isUser && message.toolCalls != null) _buildToolCalls(),

            // Message bubble
            GestureDetector(
              onLongPress: () => onReactionRequest?.call(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? const Color(0xFF6C63FF)
                      : const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  border: isUser
                      ? null
                      : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.isStreaming) _buildStreamingIndicator(),
                    MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: isUser
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.92),
                          fontSize: 15,
                          height: 1.5,
                        ),
                        code: TextStyle(
                          backgroundColor: Colors.black26,
                          color: Colors.cyan[100],
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Error action buttons
            if (!isUser && message.isError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onRetry != null)
                      _ErrorActionChip(
                        icon: Icons.refresh,
                        label: 'Retry',
                        onTap: onRetry!,
                      ),
                    if (onRetry != null && onSettingsTap != null)
                      const SizedBox(width: 8),
                    if (onSettingsTap != null)
                      _ErrorActionChip(
                        icon: Icons.settings,
                        label: 'Settings',
                        onTap: onSettingsTap!,
                      ),
                  ],
                ),
              ),

            // Reactions
            if (message.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: message.reactions.entries.map((entry) {
                    return GestureDetector(
                      onTap: () => onReactionChipTap?.call(entry.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Timestamp / inference time
            if (!message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 12, right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                    if (!message.isUser && message.inferenceTimeMs != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _formatInferenceTime(message.inferenceTimeMs!),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCalls() {
    List<dynamic> calls;
    try {
      calls = jsonDecode(message.toolCalls!) as List<dynamic>;
    } on FormatException {
      return const SizedBox.shrink();
    }

    if (calls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: calls.map((call) {
          final name = call['name'] as String? ?? 'unknown';
          final status = call['status'] as String? ?? 'done';
          final progress = call['progress'] as String?;
          final progressPercent = (call['progressPercent'] as num?)?.toDouble();
          final isExecuting = status == 'executing';
          final hasProgress = isExecuting && progress != null;

          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isExecuting
                  ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isExecuting
                    ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isExecuting)
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF6C63FF),
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.check_circle_outline,
                        size: 12,
                        color: Colors.green,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      _formatToolName(name),
                      style: TextStyle(
                        fontSize: 11,
                        color: isExecuting
                            ? const Color(0xFF6C63FF)
                            : Colors.grey[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (hasProgress) ...[
                  const SizedBox(height: 4),
                  Text(
                    progress,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                  if (progressPercent != null) ...[
                    const SizedBox(height: 2),
                    LinearProgressIndicator(
                      value: progressPercent,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF6C63FF),
                      ),
                      minHeight: 2,
                    ),
                  ],
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatToolName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Widget _buildStreamingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                message.isUser ? Colors.white70 : const Color(0xFF6C63FF),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Nova is typing...',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) return timeStr;
    final dateStr = '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';
    return '$dateStr $timeStr';
  }

  String _formatInferenceTime(int ms) {
    if (ms < 1000) return '${ms}ms';
    final seconds = ms / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }
}

class _ErrorActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ErrorActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF6C63FF)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

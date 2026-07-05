import 'package:flutter/material.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onScreenshotTap;

  const ChatBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onScreenshotTap,
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
            // Screenshot preview (only for user messages with images)
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

            // Model badge (for assistant messages)
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

            // Message bubble
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

            // Timestamp
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 12, right: 12),
              child: Text(
                _formatTime(message.timestamp),
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
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
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

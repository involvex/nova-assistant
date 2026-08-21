import 'package:flutter/material.dart';

class ModelLoadingOverlay extends StatelessWidget {
  final String status;

  const ModelLoadingOverlay({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF6C63FF)),
                const SizedBox(height: 16),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'First compile can take 1–2 minutes. Do not send yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatPrepOverlay extends StatelessWidget {
  final String status;

  const ChatPrepOverlay({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class DebugBanner extends StatelessWidget {
  final String ram;
  final String modelState;
  final String streamState;
  final String effectiveModelLabel;
  final String contextUsage;

  const DebugBanner({
    super.key,
    required this.ram,
    required this.modelState,
    required this.streamState,
    required this.effectiveModelLabel,
    required this.contextUsage,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'DEBUG  RAM: $ram  |  Model: $modelState  |  Stream: $streamState  |  '
            '$effectiveModelLabel  |  $contextUsage',
            style: const TextStyle(color: Colors.white60, fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class StatusBar extends StatelessWidget {
  final int? contextPercent;
  final Color? meterColor;
  final bool isGenerating;
  final String status;
  final bool thinkingMode;
  final VoidCallback onContextBudgetTap;

  const StatusBar({
    super.key,
    this.contextPercent,
    this.meterColor,
    required this.isGenerating,
    required this.status,
    required this.thinkingMode,
    required this.onContextBudgetTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isGenerating ? Colors.orange : Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
          if (contextPercent != null) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onContextBudgetTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (meterColor ?? Colors.grey).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (meterColor ?? Colors.grey).withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (contextPercent! / 100).clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            color: meterColor,
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Context $contextPercent%',
                        style: TextStyle(fontSize: 10, color: meterColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (thinkingMode) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology, size: 10, color: Color(0xFF6C63FF)),
                  SizedBox(width: 4),
                  Text(
                    'Thinking',
                    style: TextStyle(fontSize: 10, color: Color(0xFF6C63FF)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

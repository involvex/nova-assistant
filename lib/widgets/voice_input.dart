import 'package:flutter/material.dart';

class VoiceInputButton extends StatefulWidget {
  final void Function(String audioPath) onAudioRecorded;
  final bool isRecording;

  const VoiceInputButton({
    super.key,
    required this.onAudioRecorded,
    this.isRecording = false,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        // Trigger audio recording
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final scale = _isPressed
              ? 1.2
              : (1.0 + (_animController.value * 0.05));
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isRecording
                    ? Colors.red[600]
                    : const Color(0xFF6C63FF),
                boxShadow: [
                  BoxShadow(
                    color:
                        (widget.isRecording
                                ? Colors.red
                                : const Color(0xFF6C63FF))
                            .withValues(
                              alpha: 0.4 + (_animController.value * 0.2),
                            ),
                    blurRadius: 8 + (_animController.value * 8),
                    spreadRadius: _animController.value * 2,
                  ),
                ],
              ),
              child: Icon(
                widget.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          );
        },
      ),
    );
  }
}

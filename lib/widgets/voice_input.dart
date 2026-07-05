import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceInputButton extends StatefulWidget {
  final void Function(String audioPath) onAudioRecorded;

  const VoiceInputButton({super.key, required this.onAudioRecorded});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
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
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      debugPrint('VoiceInputButton: no microphone permission');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/nova_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);
    if (mounted) {
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (mounted) {
      setState(() => _isRecording = false);
    }

    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        widget.onAudioRecorded(path);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _toggleRecording();
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
                color: _isRecording ? Colors.red[600] : const Color(0xFF6C63FF),
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? Colors.red : const Color(0xFF6C63FF))
                        .withValues(alpha: 0.4 + (_animController.value * 0.2)),
                    blurRadius: 8 + (_animController.value * 8),
                    spreadRadius: _animController.value * 2,
                  ),
                ],
              ),
              child: Icon(
                _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
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

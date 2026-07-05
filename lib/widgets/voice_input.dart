import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceInputButton extends StatefulWidget {
  final void Function(String transcription) onTranscription;

  const VoiceInputButton({super.key, required this.onTranscription});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  String _lastWords = '';
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Speech init failed: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      if (_lastWords.isNotEmpty) {
        widget.onTranscription(_lastWords);
        _lastWords = '';
      }
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      debugPrint('Speech not available on this device');
      return;
    }

    setState(() => _isListening = true);

    _speech.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        if (result.finalResult && _lastWords.isNotEmpty) {
          widget.onTranscription(_lastWords);
          _lastWords = '';
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _toggleListening();
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
                color: _isListening
                    ? Colors.red[600]
                    : (_speechAvailable
                          ? const Color(0xFF6C63FF)
                          : Colors.grey),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? Colors.red : const Color(0xFF6C63FF))
                        .withValues(alpha: 0.4 + (_animController.value * 0.2)),
                    blurRadius: 8 + (_animController.value * 8),
                    spreadRadius: _animController.value * 2,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
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

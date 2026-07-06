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
  bool _isInitializing = true;
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
    if (!_isInitializing) setState(() => _isInitializing = true);
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Speech status: $status');
        },
        onError: (error) {
          debugPrint('Speech error: ${error.errorMsg}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Speech error: ${error.errorMsg}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('Speech init failed: $e');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isInitializing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech still initializing...'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Speech recognition not available. Check microphone permission.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isListening = true);

    _speech.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        if (result.finalResult && _lastWords.isNotEmpty) {
          widget.onTranscription(_lastWords);
          _lastWords = '';
          if (mounted) setState(() => _isListening = false);
        }
      },
      onSoundLevelChange: (level) {
        // Optional: update UI based on sound level
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

          Color bgColor;
          if (_isListening) {
            bgColor = Colors.red[600]!;
          } else if (_isInitializing) {
            bgColor = Colors.orange;
          } else if (_speechAvailable) {
            bgColor = const Color(0xFF6C63FF);
          } else {
            bgColor = Colors.grey;
          }

          return Transform.scale(
            scale: scale,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor,
                boxShadow: [
                  BoxShadow(
                    color: bgColor.withValues(
                      alpha: 0.4 + (_animController.value * 0.2),
                    ),
                    blurRadius: 8 + (_animController.value * 8),
                    spreadRadius: _animController.value * 2,
                  ),
                ],
              ),
              child: _isInitializing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
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

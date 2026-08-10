import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceInputButton extends StatefulWidget {
  final void Function(String transcription) onTranscription;

  final void Function(String partial)? onPartial;

  const VoiceInputButton({
    super.key,
    required this.onTranscription,
    this.onPartial,
  });

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
  String _initError = '';
  String _lastWords = '';
  bool _isPressed = false;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    if (!_isInitializing) setState(() => _isInitializing = true);
    try {
      final hasPermission = await Permission.microphone.isGranted;
      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _speechAvailable = false;
            _initError = 'Microphone permission required';
            _isInitializing = false;
          });
        }
        return;
      }

      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Speech status: $status');
          final ended = status == 'done' || status == 'notListening';
          if (ended && _isListening) {
            unawaited(_finishListening());
          }
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

      if (!_speechAvailable && mounted) {
        setState(() {
          _initError =
              'Speech recognition unavailable. '
              'Install Google Speech Services from Play Store.';
        });
      }
    } catch (e) {
      debugPrint('Speech init failed: $e');
      if (mounted) {
        setState(() => _initError = 'Speech services error');
      }
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
      await _finishListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _finishListening() async {
    if (_flushing) return;
    _flushing = true;
    try {
      _animController
        ..stop()
        ..reset();
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      final transcript = _lastWords.trim();
      _lastWords = '';
      if (transcript.isNotEmpty) {
        widget.onTranscription(transcript);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      if (_initError.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_initError),
            duration: const Duration(seconds: 4),
            action: _initError.contains('permission')
                ? SnackBarAction(
                    label: 'Settings',
                    onPressed: () => openAppSettings(),
                  )
                : null,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech recognition not available.'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      return;
    }

    _lastWords = '';
    _animController.repeat(reverse: true);
    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        widget.onPartial?.call(_lastWords);
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
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

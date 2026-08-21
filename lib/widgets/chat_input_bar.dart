import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/widgets/voice_input.dart';
import 'package:nova_assistant/widgets/suggestion_chip.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController inputController;
  final FocusNode inputFocus;
  final bool isGenerating;
  final bool isLoadingSuggestions;
  final List<String> followUpSuggestions;
  final int messageHardLimit;
  final int messageSoftLimit;
  final String effectiveModelLabel;
  final CustomModel? selectedCustomModel;
  final bool Function(String) canSendFor;
  final bool Function(String) isOverHardLimitFor;
  final VoidCallback onAttachPressed;
  final VoidCallback onScreenshotPressed;
  final VoidCallback onClipboardPressed;
  final VoidCallback onBulbPressed;
  final VoidCallback onRerollPressed;
  final ValueChanged<String> onSuggestionTap;
  final VoidCallback onSendPressed;
  final VoidCallback onStopPressed;
  final bool isBusy;
  final bool ttsEnabled;

  const ChatInputBar({
    super.key,
    required this.inputController,
    required this.inputFocus,
    required this.isGenerating,
    required this.isLoadingSuggestions,
    required this.followUpSuggestions,
    required this.messageHardLimit,
    required this.messageSoftLimit,
    required this.effectiveModelLabel,
    this.selectedCustomModel,
    required this.canSendFor,
    required this.isOverHardLimitFor,
    required this.onAttachPressed,
    required this.onScreenshotPressed,
    required this.onClipboardPressed,
    required this.onBulbPressed,
    required this.onRerollPressed,
    required this.onSuggestionTap,
    required this.onSendPressed,
    required this.onStopPressed,
    required this.isBusy,
    required this.ttsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: inputController,
      builder: (context, value, child) {
        final text = value.text;
        final charCount = text.length;
        final canSend = canSendFor(text);
        final counterColor = isOverHardLimitFor(text)
            ? Colors.redAccent
            : charCount > messageSoftLimit
            ? Colors.amber
            : Colors.grey[600];

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isLoadingSuggestions || followUpSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: isLoadingSuggestions
                            ? const SizedBox(
                                height: 32,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final suggestion
                                        in followUpSuggestions)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: SuggestionChip(
                                          label: suggestion,
                                          onTap: () {
                                            if (!isBusy) {
                                              onSuggestionTap(suggestion);
                                            }
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                      if (!isLoadingSuggestions &&
                          followUpSuggestions.isNotEmpty)
                        IconButton(
                          onPressed: isBusy ? null : onRerollPressed,
                          icon: const Icon(Icons.refresh, color: Colors.grey),
                          tooltip: 'More suggestions',
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    onPressed: onAttachPressed,
                    icon: const Icon(Icons.attach_file, color: Colors.grey),
                    tooltip: 'Attach',
                  ),
                  IconButton(
                    onPressed: onScreenshotPressed,
                    icon: const Icon(Icons.screenshot, color: Colors.grey),
                    tooltip: 'Capture screenshot',
                  ),
                  IconButton(
                    onPressed: onClipboardPressed,
                    icon: const Icon(Icons.content_paste, color: Colors.grey),
                    tooltip: 'Paste / analyze clipboard',
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: isBusy || isGenerating ? null : onBulbPressed,
                    icon: const Icon(
                      Icons.lightbulb_outline,
                      color: Colors.grey,
                    ),
                    tooltip: 'Suggested follow-ups',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: inputController,
                      focusNode: inputFocus,
                      maxLength: messageHardLimit,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ask Nova anything...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: const Color(0xFF1A1A2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        counterText: '',
                      ),
                      textInputAction: TextInputAction.send,
                      contextMenuBuilder: (context, editableTextState) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: [
                            ...editableTextState.contextMenuButtonItems,
                            ContextMenuButtonItem(
                              label: 'Analyze clipboard',
                              onPressed: () {
                                ContextMenuController.removeAny();
                                onClipboardPressed();
                              },
                            ),
                          ],
                        );
                      },
                      onSubmitted: (_) {
                        if (canSend) onSendPressed();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  VoiceInputButton(
                    onPartial: (partial) {
                      if (!context.mounted) return;
                      inputController.text = partial;
                      inputController.selection = TextSelection.collapsed(
                        offset: partial.length,
                      );
                    },
                    onTranscription: (transcript) {
                      if (!context.mounted || transcript.isEmpty) return;
                      inputController.text = transcript;
                      if (isGenerating || isBusy) {
                        return;
                      }
                      onSendPressed();
                    },
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      onPressed: isGenerating
                          ? onStopPressed
                          : (canSend ? onSendPressed : null),
                      icon: Icon(
                        isGenerating ? Icons.stop_circle : Icons.send_rounded,
                        color: isGenerating
                            ? Colors.redAccent
                            : (canSend ? const Color(0xFF6C63FF) : Colors.grey),
                      ),
                      tooltip: isGenerating ? 'Stop' : 'Send',
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$charCount / $messageHardLimit',
                      style: TextStyle(fontSize: 11, color: counterColor),
                    ),
                    if (selectedCustomModel == null)
                      Text(
                        effectiveModelLabel,
                        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

/// "Conversation deleted" snackbar with Undo.
///
/// Floating with a bottom margin so it never covers the chat debug banner
/// (RAM/model readout) or the input bar. Short duration — Undo is a
/// safety net, not a persistent prompt.
SnackBar conversationDeletedSnackBar({required VoidCallback onUndo}) {
  return SnackBar(
    content: const Text('Conversation deleted'),
    action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    duration: const Duration(seconds: 3),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 76),
  );
}

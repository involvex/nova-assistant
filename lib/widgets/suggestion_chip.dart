import 'package:flutter/material.dart';

/// Tappable suggestion chip for empty-state starters and follow-up prompts.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.grey[300], fontSize: 13),
        ),
      ),
    );
  }
}

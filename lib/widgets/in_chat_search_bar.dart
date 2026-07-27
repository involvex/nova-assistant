import 'package:flutter/material.dart';

class InChatSearchBar extends StatefulWidget {
  const InChatSearchBar({
    super.key,
    required this.onSearch,
    required this.onClose,
    this.matchCount = 0,
    this.currentMatch = 0,
    this.onNext,
    this.onPrevious,
  });

  final ValueChanged<String> onSearch;
  final VoidCallback onClose;
  final int matchCount;
  final int currentMatch;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  @override
  State<InChatSearchBar> createState() => _InChatSearchBarState();
}

class _InChatSearchBarState extends State<InChatSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search in conversation...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixText: widget.matchCount > 0
                      ? '${widget.currentMatch}/${widget.matchCount}'
                      : null,
                  suffixStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: widget.onSearch,
              ),
            ),
            if (widget.matchCount > 1) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.white70,
                ),
                onPressed: widget.onPrevious,
              ),
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white70,
                ),
                onPressed: widget.onNext,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () {
                _controller.clear();
                widget.onSearch('');
                widget.onClose();
              },
            ),
          ],
        ),
      ),
    );
  }
}

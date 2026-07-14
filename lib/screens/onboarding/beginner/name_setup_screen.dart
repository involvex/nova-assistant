import 'package:flutter/material.dart';

class NameSetupScreen extends StatefulWidget {
  final void Function(String name) onNameEntered;

  const NameSetupScreen({
    super.key,
    required this.onNameEntered,
  });

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  final _nameController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      _focusNode.requestFocus();
    });
  }

  void _onNameChanged() {
    final name = _nameController.text.trim();
    setState(() => _isValid = name.isNotEmpty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _continue() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      widget.onNameEntered(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Color(0xFF4CAF50),
              size: 32,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'What should Nova\ncall you?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This is how Nova will address you in conversation.',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 48),
          TextField(
            controller: _nameController,
            focusNode: _focusNode,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
            ),
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: TextStyle(
                color: Colors.grey[600],
                fontSize: 24,
              ),
              filled: true,
              fillColor: const Color(0xFF1A1A2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _isValid ? _continue() : null,
          ),
          const SizedBox(height: 24),
          _buildQuickNames(),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isValid ? _continue : null,
              style: FilledButton.styleFrom(
                backgroundColor: _isValid
                    ? const Color(0xFF6C63FF)
                    : const Color(0xFF6C63FF).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuickNames() {
    final quickNames = ['Alex', 'Sam', 'Jordan', 'Taylor', 'Morgan'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: quickNames.map((name) {
        return GestureDetector(
          onTap: () {
            _nameController.text = name;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

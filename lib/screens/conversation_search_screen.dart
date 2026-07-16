import 'package:flutter/material.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/services/chat_history_service.dart';

class ConversationSearchScreen extends StatefulWidget {
  const ConversationSearchScreen({super.key});

  @override
  State<ConversationSearchScreen> createState() =>
      _ConversationSearchScreenState();
}

class _ConversationSearchScreenState extends State<ConversationSearchScreen> {
  late final TextEditingController _controller;
  List<ChatMessage> _results = [];
  List<ChatMessage> _allMessages = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadMessages();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final messages = await ChatHistoryService.load();
    if (mounted) setState(() => _allMessages = messages);
  }

  void _onQueryChanged(String query) {
    if (query.isEmpty) {
      setState(() => _results = []);

      return;
    }
    final lowerQuery = query.toLowerCase();
    final filtered = _allMessages
        .where((msg) => msg.text.toLowerCase().contains(lowerQuery))
        .toList();
    setState(() => _results = filtered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: const Color(0xFF6C63FF),
          decoration: InputDecoration(
            hintText: 'Search conversations...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
      ),
      body: _buildResults(theme),
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_controller.text.isEmpty) {
      return Center(
        child: Text(
          'Type to search across all conversations',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final msg = _results[index];
        final snippet = _highlightSnippet(msg.text, _controller.text);

        return _ResultTile(message: msg, snippet: snippet);
      },
    );
  }

  String _highlightSnippet(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);
    if (idx == -1) {
      return text.length > 100 ? '${text.substring(0, 100)}...' : text;
    }

    final start = idx > 30 ? idx - 30 : 0;
    final end = (idx + query.length + 70 < text.length)
        ? idx + query.length + 70
        : text.length;
    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';

    return '$prefix${text.substring(start, end)}$suffix';
  }
}

class _ResultTile extends StatelessWidget {
  final ChatMessage message;
  final String snippet;

  const _ResultTile({required this.message, required this.snippet});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context, message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              message.isUser ? Icons.person_outline : Icons.auto_awesome,
              size: 16,
              color: message.isUser
                  ? Colors.grey[400]
                  : const Color(0xFF6C63FF),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snippet,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[300],
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.isUser ? 'You' : message.modelName ?? 'Assistant',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

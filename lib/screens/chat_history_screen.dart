import 'package:flutter/material.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/screens/assistant_screen.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/services/export_service.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Conversation> _conversations = [];
  List<Conversation> _filteredConversations = [];
  bool _isLoading = true;
  Conversation? _deletedConversation;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    final conversations = await ChatHistoryService.loadConversations();
    if (mounted) {
      setState(() {
        _conversations = conversations;
        _filteredConversations = conversations;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredConversations = _conversations);
    } else {
      setState(() {
        _filteredConversations = _conversations.where((c) {
          final title = c.previewTitle.toLowerCase();
          final hasMatch = title.contains(query);
          if (!hasMatch && c.title == null) {
            for (final msg in c.messages) {
              if (msg.text.toLowerCase().contains(query)) {
                return true;
              }
            }
          }
          return hasMatch;
        }).toList();
      });
    }
  }

  Map<String, List<Conversation>> _groupByDate(
    List<Conversation> conversations,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));

    final groups = <String, List<Conversation>>{};

    for (final convo in conversations) {
      final convoDate = DateTime(
        convo.updatedAt.year,
        convo.updatedAt.month,
        convo.updatedAt.day,
      );

      String group;
      if (convoDate == today) {
        group = 'Today';
      } else if (convoDate == yesterday) {
        group = 'Yesterday';
      } else if (convoDate.isAfter(thisWeekStart)) {
        group = 'This Week';
      } else {
        group = 'Earlier';
      }

      groups.putIfAbsent(group, () => []).add(convo);
    }

    return groups;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _openConversation(Conversation conversation) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AssistantScreen(conversationId: conversation.id),
      ),
    ).then((_) => _loadConversations());
  }

  Future<void> _createNewConversation() async {
    final conversation = await ChatHistoryService.createConversation();
    if (mounted) {
      _openConversation(conversation);
    }
  }

  Future<void> _deleteAllConversations() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Delete all chats?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This removes every conversation and clears the live session. '
          'Cannot be undone.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ModelOrchestrator.instance.clearHistory();
    await MemoryService.clearConversationMemory();
    if (!mounted) return;
    await _loadConversations();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All chats and RAG memory cleared')),
    );
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    _deletedConversation = conversation;
    await ChatHistoryService.deleteConversation(conversation.id);
    _loadConversations();

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Conversation deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: _undoDelete),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _undoDelete() async {
    if (_deletedConversation != null) {
      await ChatHistoryService.saveConversations([
        _deletedConversation!,
        ..._conversations,
      ]);
      _deletedConversation = null;
      _loadConversations();
    }
  }

  Future<void> _renameConversation(Conversation conversation) async {
    final controller = TextEditingController(
      text: conversation.title ?? conversation.previewTitle,
    );

    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Rename Conversation',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Conversation name',
            hintStyle: TextStyle(color: Colors.grey[600]),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[700]!),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      final updated = conversation.copyWith(title: newTitle);
      await ChatHistoryService.updateConversation(updated);
      _loadConversations();
    }
  }

  Future<void> _exportConversation(Conversation conversation) async {
    final content = await ChatHistoryService.exportConversationAsText(
      conversation.id,
    );
    if (!mounted) return;
    if (content == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export failed')));

      return;
    }

    await ExportService.instance.shareText(
      content,
      'nova_chat_${conversation.id}.txt',
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Share sheet opened')));
    }
  }

  void _showConversationMenu(Conversation conversation) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.grey),
              title: const Text(
                'Rename',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _renameConversation(conversation);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined, color: Colors.grey),
              title: const Text(
                'Export',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _exportConversation(conversation);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFFFF6B6B),
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF6B6B)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteConversation(conversation);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B6B).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
      ),
      confirmDismiss: (_) async {
        _deleteConversation(conversation);
        return false;
      },
      child: GestureDetector(
        onTap: () => _openConversation(conversation),
        onLongPress: () => _showConversationMenu(conversation),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'N',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.previewTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation.lastMessageSnippet,
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(conversation.updatedAt),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${conversation.messageCount} msgs',
                    style: TextStyle(color: Colors.grey[700], fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey[700]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Chat History',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (_conversations.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.grey),
              tooltip: 'Delete all',
              onPressed: _deleteAllConversations,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                  )
                : _filteredConversations.isEmpty
                ? _buildEmptyState()
                : _buildConversationList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewConversation,
        backgroundColor: const Color(0xFF6C63FF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'New Chat',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isEmpty
                ? 'No conversations yet'
                : 'No matching conversations',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isEmpty
                ? 'Start a new chat to get started'
                : 'Try a different search term',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList() {
    final groups = _groupByDate(_filteredConversations);
    final orderedGroups = ['Today', 'Yesterday', 'This Week', 'Earlier'];
    final sections = orderedGroups.where((g) => groups.containsKey(g)).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: sections.length,
      itemExtent: 88,
      itemBuilder: (context, index) {
        final group = sections[index];
        final conversations = groups[group]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) const SizedBox(height: 16),
            _buildSectionHeader(group),
            ...conversations.map(_buildConversationTile),
          ],
        );
      },
    );
  }
}

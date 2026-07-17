import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nova_assistant/screens/assistant_screen.dart';
import 'package:nova_assistant/screens/memory_management_screen.dart';
import 'package:nova_assistant/services/memory_service.dart';
import 'package:nova_assistant/services/user_memory_service.dart';

/// Claude-style overview of stored vs live-derived user memories.
class UserMemoryOverviewScreen extends StatefulWidget {
  const UserMemoryOverviewScreen({super.key});

  @override
  State<UserMemoryOverviewScreen> createState() =>
      _UserMemoryOverviewScreenState();
}

class _UserMemoryOverviewScreenState extends State<UserMemoryOverviewScreen> {
  final _service = UserMemoryService.instance;
  List<StoredMemoryItem> _stored = [];
  List<DerivedMemoryItem> _derived = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stored = await _service.listStored();
    final derived = await _service.listDerived();
    if (!mounted) return;
    setState(() {
      _stored = stored;
      _derived = derived;
      _loading = false;
    });
  }

  String get _subtitle {
    final latest = _service.latestUpdate(stored: _stored, derived: _derived);
    if (latest == null) return 'No entries yet';
    final d =
        '${latest.year.toString().padLeft(4, '0')}-'
        '${latest.month.toString().padLeft(2, '0')}-'
        '${latest.day.toString().padLeft(2, '0')}';

    return 'Updated $d from your chats';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Memory overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _subtitle,
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _sectionHeader('Saved', Icons.bookmark_outline),
                      if (_stored.isEmpty)
                        _emptyCard('No saved memories yet.')
                      else
                        ..._stored.map(_buildStoredCard),
                      const SizedBox(height: 20),
                      _sectionHeader('Derived', Icons.auto_awesome),
                      if (_derived.isEmpty)
                        _emptyCard(
                          'No derived hints from chats. '
                          'Enable RAG Memory in Settings so chat history '
                          'can appear here.',
                        )
                      else
                        ..._derived.map(_buildDerivedCard),
                      const SizedBox(height: 24),
                      _primaryButton(
                        label: 'Ask what Nova knows',
                        icon: Icons.chat_bubble_outline,
                        onPressed: _openAskSheet,
                      ),
                      const SizedBox(height: 10),
                      _secondaryButton(
                        label: 'List as chat prompt',
                        icon: Icons.list_alt,
                        onPressed: _openInventoryInChat,
                      ),
                      const SizedBox(height: 10),
                      _secondaryButton(
                        label: 'Manage memories',
                        icon: Icons.open_in_new,
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const MemoryManagementScreen(),
                            ),
                          );
                          await _load();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(message, style: TextStyle(color: Colors.grey[500])),
    );
  }

  Widget _buildStoredCard(StoredMemoryItem item) {
    final date = _fmtDate(item.createdAt);
    final sourceLabel = item.source == StoredMemorySource.promoted
        ? 'promoted'
        : 'manual';

    return Card(
      color: const Color(0xFF1A1A2E),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(item.title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '${item.content}\n$date · $sourceLabel',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await _editStored(item);
            } else if (v == 'delete') {
              await MemoryService.deleteCustomMemory(item.id);
              await _load();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDerivedCard(DerivedMemoryItem item) {
    final origin = item.origin == DerivedMemoryOrigin.rag ? 'Chat' : 'Summary';

    return Card(
      color: const Color(0xFF1A1A2E),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          item.text,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_fmtDate(item.derivedAt)} · $origin',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'promote') {
              await _service.promoteDerived(item);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved to memories')),
              );
              await _load();
            } else if (v == 'dismiss') {
              await _service.dismissDerived(item.id);
              await _load();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'promote', child: Text('Promote')),
            PopupMenuItem(value: 'dismiss', child: Text('Dismiss')),
          ],
        ),
      ),
    );
  }

  Future<void> _editStored(StoredMemoryItem item) async {
    final titleController = TextEditingController(text: item.title);
    final contentController = TextEditingController(text: item.content);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Edit memory', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentController,
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Information'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MemoryService.updateCustomMemory(
      item.id,
      titleController.text.trim(),
      contentController.text.trim(),
    );
    await _load();
  }

  Future<void> _openAskSheet() async {
    final controller = TextEditingController();
    final question = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ask what Nova knows',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Answer only from saved and derived entries.',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'e.g. What do you know about my projects?',
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Ask'),
              ),
            ],
          ),
        );
      },
    );
    if (question == null || question.isEmpty || !mounted) return;

    final language = await UserMemoryService.loadAssistantLanguage();
    final german = language.useGermanInventory;
    final inventory = await _service.buildInventoryList(german: german);
    final prompt = german
        ? 'Beantworte die Frage nur anhand der folgenden '
              'Speicherübersicht. Markiere Quellen als [gespeichert] oder '
              '[abgeleitet]. Erfinde nichts.\n\n'
              'Übersicht:\n$inventory\n\nFrage: $question'
        : 'Answer the question using only the following memory inventory. '
              'Cite sources as [saved] or [derived]. Do not invent facts.\n\n'
              'Inventory:\n$inventory\n\nQuestion: $question';

    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AssistantScreen(initialPrompt: prompt),
      ),
    );
  }

  Future<void> _openInventoryInChat() async {
    final language = await UserMemoryService.loadAssistantLanguage();
    final german = language.useGermanInventory;
    final inventory = await _service.buildInventoryList(german: german);
    final promptTemplate = UserMemoryService.inventoryChatPromptFor(language);
    final contextLabel = german
        ? 'Kontext (deterministische Übersicht — formatiere danach):'
        : 'Context (deterministic inventory — format accordingly):';
    final prompt = '$promptTemplate\n\n$contextLabel\n$inventory';

    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt copied — opening chat…')),
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AssistantScreen(initialPrompt: prompt),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFD97757),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

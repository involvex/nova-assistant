import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nova_assistant/models/note.dart';
import 'package:nova_assistant/services/note_service.dart';
import 'package:nova_assistant/services/export_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _noteService = NoteService.instance;
  List<Note> _notes = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();
  StreamSubscription<List<Note>>? _notesSub;

  @override
  void initState() {
    super.initState();
    _notes = _noteService.notes;
    _notesSub = _noteService.notesStream.listen((notes) {
      if (mounted) setState(() => _notes = notes);
    });
  }

  @override
  void dispose() {
    _notesSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Note> get _filteredNotes {
    if (_searchQuery.isEmpty) return _notes;
    return _noteService.searchNotes(_searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Notes'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              ExportService.instance.shareNotes(format: value);
            },
            icon: const Icon(Icons.share),
            tooltip: 'Export notes',
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'json', child: Text('Export as JSON')),
              const PopupMenuItem(value: 'text', child: Text('Export as text')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search notes...',
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                prefixIcon:
                    Icon(Icons.search, color: Colors.grey[600], size: 20),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Expanded(
            child: _filteredNotes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_alt_outlined,
                            size: 64, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No notes yet'
                              : 'No matching notes',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ask Nova to create a note, or tap +',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredNotes.length,
                    itemBuilder: (context, index) => _NoteCard(
                      note: _filteredNotes[index],
                      onDelete: () =>
                          _noteService.deleteNote(_filteredNotes[index].id),
                      onTogglePin: () =>
                          _noteService.togglePin(_filteredNotes[index].id),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: const Color(0xFF6C63FF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final tagController = TextEditingController();
    List<String> tags = [];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New Note',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                style: const TextStyle(color: Colors.white),
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Write your note...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: tagController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      onSubmitted: (value) {
                        final tag = value.trim();
                        if (tag.isNotEmpty && !tags.contains(tag)) {
                          setModalState(() {
                            tags = [...tags, tag];
                            tagController.clear();
                          });
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Add tag...',
                        hintStyle:
                            TextStyle(color: Colors.grey[600], fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0D0D1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      final tag = tagController.text.trim();
                      if (tag.isNotEmpty && !tags.contains(tag)) {
                        setModalState(() {
                          tags = [...tags, tag];
                          tagController.clear();
                        });
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    color: const Color(0xFF6C63FF),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags
                      .map(
                        (tag) => Chip(
                          label:
                              Text(tag, style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              const Color(0xFF6C63FF).withValues(alpha: 0.15),
                          labelStyle: const TextStyle(color: Color(0xFF6C63FF)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => setModalState(() {
                            tags = tags.where((t) => t != tag).toList();
                          }),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (titleController.text.isNotEmpty &&
                      contentController.text.isNotEmpty) {
                    _noteService.createNote(
                      title: titleController.text.trim(),
                      content: contentController.text.trim(),
                      tags: tags,
                    );
                    Navigator.pop(ctx);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save Note'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _NoteCard({
    required this.note,
    required this.onDelete,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(note.id),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: note.isPinned
              ? const Color(0xFF6C63FF).withValues(alpha: 0.08)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: note.isPinned
                ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (note.isPinned) ...[
                  const Icon(Icons.push_pin,
                      size: 14, color: Color(0xFF6C63FF)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'pin') onTogglePin();
                    if (value == 'delete') onDelete();
                  },
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child:
                          Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              note.content,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (note.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: note.tags
                    .map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF6C63FF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6C63FF),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:nova_assistant/models/note.dart';

class NoteService {
  static NoteService? _instance;
  static NoteService get instance => _instance ??= NoteService._();
  NoteService._();

  static const _prefsKey = 'nova_notes';
  static const _uuid = Uuid();

  StreamController<List<Note>> _notesController =
      StreamController<List<Note>>.broadcast();
  Stream<List<Note>> get notesStream => _notesController.stream;

  List<Note> _notes = [];

  List<Note> get notes => List.unmodifiable(_notes);

  List<Note> get pinnedNotes => _notes.where((n) => n.isPinned).toList();

  Future<void> initialize() async {
    if (_notesController.isClosed) {
      _notesController = StreamController<List<Note>>.broadcast();
    }
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _notes =
            list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        _notes = [];
      }
    } else {
      _notes = [];
    }
    _notifyListeners();
  }

  Future<Note> createNote({
    required String title,
    required String content,
    List<String> tags = const [],
    bool isPinned = false,
  }) async {
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      tags: tags,
      isPinned: isPinned,
    );
    _notes.insert(0, note);
    await _save();
    _notifyListeners();
    return note;
  }

  Future<void> updateNote(Note note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      _notes[index] = note;
      await _save();
      _notifyListeners();
    }
  }

  Future<void> deleteNote(String noteId) async {
    _notes.removeWhere((n) => n.id == noteId);
    await _save();
    _notifyListeners();
  }

  Future<void> togglePin(String noteId) async {
    final index = _notes.indexWhere((n) => n.id == noteId);
    if (index != -1) {
      _notes[index] = _notes[index].copyWith(isPinned: !_notes[index].isPinned);
      await _save();
      _notifyListeners();
    }
  }

  List<Note> searchNotes(String query) {
    final lower = query.toLowerCase();
    return _notes.where((n) {
      return n.title.toLowerCase().contains(lower) ||
          n.content.toLowerCase().contains(lower) ||
          n.tags.any((t) => t.toLowerCase().contains(lower));
    }).toList();
  }

  List<Note> getNotesByTag(String tag) =>
      _notes.where((n) => n.tags.contains(tag)).toList();

  Set<String> get allTags {
    final tags = <String>{};
    for (final note in _notes) {
      tags.addAll(note.tags);
    }
    return tags;
  }

  /// Handle tool calls from the AI model.
  Future<Map<String, dynamic>> executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    switch (toolName) {
      case 'create_note':
        return _handleCreateNote(args);
      case 'search_notes':
        return _handleSearchNotes(args);
      case 'list_notes':
        return _handleListNotes(args);
      default:
        return {'success': false, 'error': 'Unknown note tool: $toolName'};
    }
  }

  Future<Map<String, dynamic>> _handleCreateNote(
    Map<String, dynamic> args,
  ) async {
    final title = args['title'] as String?;
    if (title == null || title.isEmpty) {
      return {'success': false, 'error': 'Title is required'};
    }

    final content = args['content'] as String? ?? '';
    final tagsStr = args['tags'] as String?;
    final tags = tagsStr != null
        ? tagsStr.split(',').map((t) => t.trim()).toList()
        : <String>[];

    final note = await createNote(
      title: title,
      content: content,
      tags: tags,
    );

    return {
      'success': true,
      'noteId': note.id,
      'title': note.title,
      'message': 'Note saved: ${note.title}',
    };
  }

  Future<Map<String, dynamic>> _handleSearchNotes(
    Map<String, dynamic> args,
  ) async {
    final query = args['query'] as String?;
    if (query == null || query.isEmpty) {
      return {'success': false, 'error': 'Search query is required'};
    }

    final results = searchNotes(query);
    if (results.isEmpty) {
      return {
        'success': true,
        'message': 'No notes found for: $query',
        'notes': <Map<String, dynamic>>[],
      };
    }

    return {
      'success': true,
      'count': results.length,
      'notes': results
          .take(10)
          .map((n) => {
                'id': n.id,
                'title': n.title,
                'preview': n.content.length > 100
                    ? '${n.content.substring(0, 100)}...'
                    : n.content,
                'tags': n.tags,
                'updatedAt': n.updatedAt.toIso8601String(),
              })
          .toList(),
      'message': 'Found ${results.length} note(s) matching "$query"',
    };
  }

  Future<Map<String, dynamic>> _handleListNotes(
    Map<String, dynamic> args,
  ) async {
    final all = _notes;
    if (all.isEmpty) {
      return {
        'success': true,
        'message': 'No notes yet',
        'notes': <Map<String, dynamic>>[],
      };
    }

    final pinned = pinnedNotes;
    return {
      'success': true,
      'count': all.length,
      'pinnedCount': pinned.length,
      'notes': all
          .take(20)
          .map((n) => {
                'id': n.id,
                'title': n.title,
                'preview': n.content.length > 80
                    ? '${n.content.substring(0, 80)}...'
                    : n.content,
                'tags': n.tags,
                'isPinned': n.isPinned,
              })
          .toList(),
      'message': '${all.length} note(s) total, ${pinned.length} pinned',
    };
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_notes.map((n) => n.toJson()).toList());
    await prefs.setString(_prefsKey, json);
  }

  void _notifyListeners() {
    _notesController.add(notes);
  }

  Future<void> dispose() async {
    await _notesController.close();
  }

  static void reset() {
    _instance = null;
  }
}

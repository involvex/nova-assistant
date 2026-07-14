import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nova_assistant/models/task.dart';
import 'package:nova_assistant/services/task_service.dart';
import 'package:nova_assistant/services/note_service.dart';

class ExportService {
  static ExportService? _instance;
  static ExportService get instance => _instance ??= ExportService._();
  ExportService._();

  static const _channel = MethodChannel('dev.nova.assistant/share');

  String exportTasksAsJson() {
    final tasks = TaskService.instance.tasks;
    final json = tasks.map((t) => t.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toIso8601String(),
      'task_count': tasks.length,
      'tasks': json,
    });
  }

  String exportTasksAsText() {
    final tasks = TaskService.instance.tasks;
    final buffer = StringBuffer();
    buffer.writeln('Tasks Export — ${DateTime.now()}');
    buffer.writeln('${tasks.length} task(s)');
    buffer.writeln();

    for (final task in tasks) {
      final status = task.status == TaskStatus.completed ? '[DONE]' : '[TODO]';
      final priority = task.priority.name.toUpperCase();
      buffer.writeln('$status [$priority] ${task.title}');
      if (task.description != null && task.description!.isNotEmpty) {
        buffer.writeln('  ${task.description}');
      }
      if (task.dueDate != null) {
        buffer.writeln(
          '  Due: ${task.dueDate!.year}-${task.dueDate!.month.toString().padLeft(2, '0')}-${task.dueDate!.day.toString().padLeft(2, '0')}',
        );
      }
      if (task.tags.isNotEmpty) {
        buffer.writeln('  Tags: ${task.tags.join(', ')}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String exportNotesAsJson() {
    final notes = NoteService.instance.notes;
    final json = notes.map((n) => n.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toIso8601String(),
      'note_count': notes.length,
      'notes': json,
    });
  }

  String exportNotesAsText() {
    final notes = NoteService.instance.notes;
    final buffer = StringBuffer();
    buffer.writeln('Notes Export — ${DateTime.now()}');
    buffer.writeln('${notes.length} note(s)');
    buffer.writeln();

    for (final note in notes) {
      final pin = note.isPinned ? ' *PINNED*' : '';
      buffer.writeln('## ${note.title}$pin');
      buffer.writeln(note.content);
      if (note.tags.isNotEmpty) {
        buffer.writeln('Tags: ${note.tags.join(', ')}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  Future<void> shareTasks({String format = 'json'}) async {
    final content =
        format == 'json' ? exportTasksAsJson() : exportTasksAsText();
    final fileName = format == 'json' ? 'nova_tasks.json' : 'nova_tasks.txt';
    await _shareText(content, fileName);
  }

  Future<void> shareNotes({String format = 'json'}) async {
    final content =
        format == 'json' ? exportNotesAsJson() : exportNotesAsText();
    final fileName = format == 'json' ? 'nova_notes.json' : 'nova_notes.txt';
    await _shareText(content, fileName);
  }

  Future<void> _shareText(String text, String subject) async {
    try {
      await _channel.invokeMethod('shareText', {
        'text': text,
        'subject': subject,
      });
    } on MissingPluginException {
      // Fallback: write to temp file for manual sharing
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$subject');
      await file.writeAsString(text);
    }
  }
}

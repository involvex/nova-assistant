import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/services/note_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoteService service;

  setUp(() async {
    NoteService.reset();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    service = NoteService.instance;
    await service.initialize();
  });

  tearDown(() async {
    await service.dispose();
  });

  group('NoteService', () {
    test('initializes with empty notes list', () {
      expect(service.notes, isEmpty);
    });

    group('createNote', () {
      test('creates a note with correct fields', () async {
        final note = await service.createNote(
          title: 'Test Note',
          content: 'Some content here',
        );

        expect(note.title, 'Test Note');
        expect(note.content, 'Some content here');
        expect(note.isPinned, false);
      });

      test('note appears in notes list', () async {
        await service.createNote(title: 'Note 1', content: 'Body');
        expect(service.notes.length, 1);
        expect(service.notes[0].title, 'Note 1');
      });
    });

    group('deleteNote', () {
      test('removes note from list', () async {
        final note = await service.createNote(title: 'Delete me', content: 'x');
        expect(service.notes.length, 1);

        await service.deleteNote(note.id);
        expect(service.notes, isEmpty);
      });
    });

    group('searchNotes', () {
      test('finds notes by title', () async {
        await service.createNote(title: 'Grocery List', content: 'milk, eggs');
        await service.createNote(
          title: 'Meeting Notes',
          content: 'action items',
        );

        final results = service.searchNotes('grocery');
        expect(results.length, 1);
        expect(results[0].title, 'Grocery List');
      });

      test('finds notes by content', () async {
        await service.createNote(title: 'Ideas', content: 'build a chatbot');

        final results = service.searchNotes('chatbot');
        expect(results.length, 1);
      });

      test('returns empty for no match', () async {
        await service.createNote(title: 'Hello', content: 'world');
        final results = service.searchNotes('zzz');
        expect(results, isEmpty);
      });
    });

    group('togglePin', () {
      test('toggles pin state', () async {
        final note = await service.createNote(title: 'Pinnable', content: 'x');
        expect(note.isPinned, false);

        await service.togglePin(note.id);
        expect(service.notes[0].isPinned, true);

        await service.togglePin(note.id);
        expect(service.notes[0].isPinned, false);
      });
    });

    group('persistence', () {
      test('notes survive reinitialize', () async {
        await service.createNote(title: 'Persist me', content: 'saved');
        await service.dispose();

        final service2 = NoteService.instance;
        await service2.initialize();
        expect(service2.notes.length, 1);
        expect(service2.notes[0].title, 'Persist me');
      });
    });

    group('executeTool', () {
      test('create_note creates a note', () async {
        final result = await service.executeTool('create_note', {
          'title': 'AI Note',
          'content': 'Generated content',
        });

        expect(result['success'], true);
        expect(service.notes.length, 1);
        expect(service.notes[0].title, 'AI Note');
      });

      test('search_notes returns matching notes', () async {
        await service.createNote(title: 'Flutter Tips', content: 'use const');
        final result = await service.executeTool('search_notes', {
          'query': 'flutter',
        });

        expect(result['success'], true);
        expect(result['count'], 1);
      });

      test('list_notes returns all notes', () async {
        await service.createNote(title: 'A', content: '1');
        await service.createNote(title: 'B', content: '2');
        final result = await service.executeTool('list_notes', {});

        expect(result['success'], true);
        expect(result['count'], 2);
      });
    });
  });
}

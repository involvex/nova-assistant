import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/user_memory_service.dart';

void main() {
  group('UserMemoryService.formatInventoryList', () {
    test('lists stored before derived and sorts by date ascending', () {
      final stored = [
        StoredMemoryItem(
          id: '2',
          title: 'Later',
          content: 'Ich mag Tee',
          createdAt: DateTime(2026, 6, 20),
        ),
        StoredMemoryItem(
          id: '1',
          title: 'Earlier',
          content: 'Ich mag Kaffee',
          createdAt: DateTime(2026, 6, 10),
        ),
      ];
      final derived = [
        DerivedMemoryItem(
          id: 'd2',
          text: 'Ich baue Apps',
          derivedAt: DateTime(2026, 6, 15),
          origin: DerivedMemoryOrigin.rag,
          originRef: 't2',
        ),
        DerivedMemoryItem(
          id: 'd1',
          text: 'Ich lerne Dart',
          derivedAt: DateTime(2026, 6, 5),
          origin: DerivedMemoryOrigin.summary,
          originRef: 'c1',
        ),
      ];

      final formatted = UserMemoryService.instance.formatInventoryList(
        stored: stored,
        derived: derived,
      );

      expect(formatted.startsWith('```'), isTrue);
      expect(formatted.endsWith('```'), isTrue);

      final lines = formatted
          .split('\n')
          .where((l) => l.isNotEmpty && !l.startsWith('```'))
          .toList();

      expect(lines.length, 4);
      expect(lines[0], startsWith('1. [saved](2026-06-10)'));
      expect(lines[0], contains('Ich mag Kaffee'));
      expect(lines[1], startsWith('2. [saved](2026-06-20)'));
      expect(lines[2], startsWith('3. [derived](2026-06-05)'));
      expect(lines[2], contains('Ich lerne Dart'));
      expect(lines[3], startsWith('4. [derived](2026-06-15)'));
    });

    test('german tags when german: true', () {
      final stored = [
        StoredMemoryItem(
          id: '1',
          title: 'Coffee',
          content: 'Ich mag Kaffee',
          createdAt: DateTime(2026, 6, 10),
        ),
      ];
      final derived = [
        DerivedMemoryItem(
          id: 'd1',
          text: 'Ich lerne Dart',
          derivedAt: DateTime(2026, 6, 5),
          origin: DerivedMemoryOrigin.summary,
          originRef: 'c1',
        ),
      ];

      final formatted = UserMemoryService.instance.formatInventoryList(
        stored: stored,
        derived: derived,
        german: true,
      );

      expect(formatted, contains('[gespeichert]'));
      expect(formatted, contains('[abgeleitet]'));
    });

    test('empty inventory returns placeholder code block', () {
      final formatted = UserMemoryService.instance.formatInventoryList(
        stored: const [],
        derived: const [],
      );
      expect(formatted, contains('no entries'));
    });

    test('firstPersonText prefixes when needed', () {
      final item = StoredMemoryItem(
        id: '1',
        title: 'Name',
        content: 'Involvex',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(item.firstPersonText(), startsWith('I:'));
      expect(item.firstPersonText(german: true), startsWith('Ich:'));

      final already = StoredMemoryItem(
        id: '2',
        title: 'x',
        content: 'Ich bin vegetarisch',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(already.firstPersonText(), 'Ich bin vegetarisch');
    });
  });
}

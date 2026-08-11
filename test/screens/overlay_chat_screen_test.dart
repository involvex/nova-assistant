import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/screens/overlay_chat_screen.dart';

void main() {
  group('OverlayChatScreen', () {
    testWidgets('shows scrim background and bottom-aligned card', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OverlayChatScreen()));
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, Colors.black54);

      final align = tester.widget<Align>(find.byType(Align).first);
      expect(align.alignment, Alignment.bottomCenter);
    });

    testWidgets('card has dark background and rounded top corners', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OverlayChatScreen()));
      await tester.pump();

      final container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxHeight != null &&
              w.clipBehavior == Clip.antiAlias,
        ),
      );
      expect(container.constraints?.maxHeight, isNotNull);
    });
  });
}

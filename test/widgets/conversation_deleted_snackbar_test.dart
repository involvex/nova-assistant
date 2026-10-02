import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/widgets/conversation_deleted_snackbar.dart';

void main() {
  group('conversationDeletedSnackBar', () {
    test('floats above the debug banner with short duration', () {
      final SnackBar bar = conversationDeletedSnackBar(onUndo: () {});

      expect(bar.behavior, SnackBarBehavior.floating);
      expect(bar.duration, const Duration(seconds: 3));
      final double bottom = bar.margin!.resolve(TextDirection.ltr).bottom;
      expect(bottom, greaterThanOrEqualTo(72));
      expect(bar.action?.label, 'Undo');
    });

    test('undo callback fires', () {
      bool called = false;
      final SnackBar bar = conversationDeletedSnackBar(
        onUndo: () => called = true,
      );

      bar.action?.onPressed.call();

      expect(called, isTrue);
    });
  });
}

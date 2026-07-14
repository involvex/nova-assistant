import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/tool_progress.dart';

void main() {
  group('ToolProgress', () {
    test('creates with required fields', () {
      final progress = ToolProgress(
        toolName: 'set_alarm',
        stage: ToolProgressStage.executing,
        message: 'Working...',
      );

      expect(progress.toolName, 'set_alarm');
      expect(progress.stage, ToolProgressStage.executing);
      expect(progress.message, 'Working...');
      expect(progress.percent, isNull);
    });

    test('creates with percent and data', () {
      final progress = ToolProgress(
        toolName: 'download',
        stage: ToolProgressStage.processing,
        message: '50% done',
        percent: 0.5,
        data: {'url': 'https://example.com/file.bin'},
      );

      expect(progress.percent, 0.5);
      expect(progress.data, {'url': 'https://example.com/file.bin'});
    });

    test('toMap/fromMap roundtrips correctly', () {
      final original = ToolProgress(
        toolName: 'test_tool',
        stage: ToolProgressStage.done,
        message: 'Done!',
        percent: 1.0,
      );

      final map = original.toMap();
      final restored = ToolProgress.fromMap(map);

      expect(restored.toolName, original.toolName);
      expect(restored.stage, original.stage);
      expect(restored.message, original.message);
      expect(restored.percent, original.percent);
    });

    test('fromMap handles all stages', () {
      for (final stage in ToolProgressStage.values) {
        final map = {'toolName': 'x', 'stage': stage.name, 'message': 'test'};
        final progress = ToolProgress.fromMap(map);
        expect(progress.stage, stage);
      }
    });

    test('fromMap defaults unknown stage to executing', () {
      final map = {
        'toolName': 'x',
        'stage': 'unknown_stage',
        'message': 'test',
      };
      final progress = ToolProgress.fromMap(map);
      expect(progress.stage, ToolProgressStage.executing);
    });

    test('fromMap handles missing fields gracefully', () {
      final map = <String, dynamic>{'stage': 'error'};
      final progress = ToolProgress.fromMap(map);
      expect(progress.toolName, '');
      expect(progress.stage, ToolProgressStage.error);
      expect(progress.message, isNull);
      expect(progress.percent, isNull);
    });
  });
}

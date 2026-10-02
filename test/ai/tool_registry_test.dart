import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/tools/core/tool_context.dart';
import 'package:nova_assistant/tools/core/tool_registry.dart';
import 'package:nova_assistant/tools/core/tool_result.dart';
import 'package:nova_assistant/tools/implementations/built_in_tools.dart';

Future<Map<String, Object?>> _okHandler(
  String toolId,
  Map<String, Object?> args,
) async {
  return <String, Object?>{'success': true, 'echo': toolId};
}

void main() {
  setUp(() {
    ToolRegistry.clearForTesting();
  });

  tearDown(() {
    ToolRegistry.clearForTesting();
  });

  group('ToolRegistry', () {
    test('covers full legacy surface', () {
      ToolRegistry.registerAll(allNovaTools(handler: _okHandler));

      for (final String id in <String>[
        'get_time',
        'set_alarm',
        'cancel_alarm',
        'open_app',
        'search_web',
        'get_weather',
        'send_sms',
        'open_settings',
        'take_screenshot',
        'generate_image',
        'open_app_info',
        'open_battery_settings',
        'create_task',
        'list_tasks',
        'complete_task',
        'create_note',
        'search_notes',
        'list_notes',
        'start_audio_recording',
        'stop_audio_recording',
        'webfetch',
      ]) {
        expect(ToolRegistry.tryGet(id), isNotNull, reason: id);
      }
    });

    test('open_app validates package arg', () async {
      ToolRegistry.registerAll(allNovaTools(handler: _okHandler));
      const ToolContext context = ToolContext(sessionId: 's1');

      final ToolResult missing = await ToolRegistry.execute(
        'open_app',
        context,
        const <String, Object?>{},
      );
      expect(missing.success, isFalse);

      final ToolResult ok = await ToolRegistry.execute(
        'open_app',
        context,
        const <String, Object?>{'package': 'com.example.app'},
      );
      expect(ok.success, isTrue);
    });

    test('unknown tool throws', () {
      expect(() => ToolRegistry.get('does_not_exist'), throwsStateError);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/tools/tool_definitions.dart';

void main() {
  group('NovaTools', () {
    test('all tools list is not empty', () {
      expect(NovaTools.all, isNotEmpty);
    });

    test('all tools list has 15 tools', () {
      expect(NovaTools.all.length, 15);
    });

    test('each tool has a unique name', () {
      final names = NovaTools.all.map((t) => t.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('each tool has a non-empty description', () {
      for (final tool in NovaTools.all) {
        expect(tool.description, isNotEmpty, reason: 'Tool: ${tool.name}');
      }
    });

    test('each tool has a parameters map with type=object', () {
      for (final tool in NovaTools.all) {
        expect(tool.parameters['type'], 'object', reason: 'Tool: ${tool.name}');
      }
    });

    test('each tool has a properties map', () {
      for (final tool in NovaTools.all) {
        expect(
          tool.parameters['properties'],
          isA<Map<String, Object>>(),
          reason: 'Tool: ${tool.name}',
        );
      }
    });

    group('getTime tool', () {
      test('has correct name and description', () {
        expect(NovaTools.getTime.name, 'get_time');
        expect(NovaTools.getTime.description, contains('current time'));
      });

      test('has no required parameters', () {
        expect(NovaTools.getTime.parameters['required'], isNull);
      });
    });

    group('setAlarm tool', () {
      test('has correct name', () {
        expect(NovaTools.setAlarm.name, 'set_alarm');
      });

      test('requires hour and minute', () {
        final required = NovaTools.setAlarm.parameters['required'] as List;
        expect(required, containsAll(['hour', 'minute']));
      });

      test('has hour parameter with integer type', () {
        final props = NovaTools.setAlarm.parameters['properties'] as Map;
        expect(props['hour']['type'], 'integer');
      });
    });

    group('openApp tool', () {
      test('requires package parameter', () {
        final required = NovaTools.openApp.parameters['required'] as List;
        expect(required, contains('package'));
      });

      test('package parameter is string type', () {
        final props = NovaTools.openApp.parameters['properties'] as Map;
        expect(props['package']['type'], 'string');
      });
    });

    group('searchWeb tool', () {
      test('requires query parameter', () {
        final required = NovaTools.searchWeb.parameters['required'] as List;
        expect(required, contains('query'));
      });
    });

    group('sendSms tool', () {
      test('requires phone and message', () {
        final required = NovaTools.sendSms.parameters['required'] as List;
        expect(required, containsAll(['phone', 'message']));
      });
    });

    group('openSettings tool', () {
      test('has no parameters', () {
        final props = NovaTools.openSettings.parameters['properties'] as Map;
        expect(props, isEmpty);
      });
    });

    group('takeScreenshot tool', () {
      test('has no parameters', () {
        final props = NovaTools.takeScreenshot.parameters['properties'] as Map;
        expect(props, isEmpty);
      });

      test('description mentions capturing screen', () {
        expect(NovaTools.takeScreenshot.description, contains('screen'));
      });
    });
  });
}

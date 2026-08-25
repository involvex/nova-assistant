import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/tools/tool_definitions.dart';

void main() {
  group('NovaTools', () {
    test('all tools list is not empty', () {
      expect(NovaTools.all, isNotEmpty);
    });

    test('all tools list has expected built-in count', () {
      // Built-ins include open_app_info + open_battery_settings + audio
      // recording tools + webfetch; force_stop_app is only added when
      // Advanced Shizuku force-stop is enabled.
      expect(NovaTools.all.length, 21);
      expect(NovaTools.all.any((t) => t.name == 'open_app_info'), isTrue);
      expect(
        NovaTools.all.any((t) => t.name == 'open_battery_settings'),
        isTrue,
      );
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

      test('allows hour/minute or duration_minutes', () {
        final required = NovaTools.setAlarm.parameters['required'] as List;
        // Relative timers use duration_minutes; absolute times use hour/minute.
        expect(required, isEmpty);
        final props = NovaTools.setAlarm.parameters['properties'] as Map;
        expect(props.containsKey('hour'), isTrue);
        expect(props.containsKey('minute'), isTrue);
        expect(props.containsKey('duration_minutes'), isTrue);
      });

      test('has hour parameter with integer type', () {
        final props = NovaTools.setAlarm.parameters['properties'] as Map;
        expect(props['hour']['type'], 'integer');
      });

      test('description mentions relative timers', () {
        expect(NovaTools.setAlarm.description, contains('duration_minutes'));
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

    group('webFetch tool', () {
      test('is included in all tools', () {
        expect(NovaTools.all.any((t) => t.name == 'webfetch'), isTrue);
      });

      test('has correct name and description', () {
        expect(NovaTools.webFetch.name, 'webfetch');
        expect(NovaTools.webFetch.description, contains('URL'));
        // Distinct from search_web: reads a page instead of opening a browser.
        expect(NovaTools.webFetch.description, contains('search_web'));
      });

      test('requires url parameter', () {
        final required = NovaTools.webFetch.parameters['required'] as List;
        expect(required, contains('url'));
      });

      test('url parameter is string type', () {
        final props = NovaTools.webFetch.parameters['properties'] as Map;
        expect(props['url']['type'], 'string');
        expect(props.containsKey('max_length'), isTrue);
      });
    });
  });
}

import 'package:nova_assistant/platform/tool_executor_service.dart';
import 'package:nova_assistant/tools/core/nova_tool.dart';
import 'package:nova_assistant/tools/core/tool_context.dart';
import 'package:nova_assistant/tools/core/tool_result.dart';

/// Handler invoked by tools to perform the platform call.
/// Default forwards to [ToolExecutorService]; tests inject fakes.
typedef ToolHandler = Future<Map<String, Object?>> Function(
  String toolId,
  Map<String, Object?> args,
);

Future<Map<String, Object?>> defaultToolHandler(
  String toolId,
  Map<String, Object?> args,
) async {
  final Map<String, dynamic> raw = await ToolExecutorService.instance
      .executeTool(toolId, Map<String, dynamic>.from(args));
  final Map<String, Object?> converted = <String, Object?>{};
  for (final MapEntry<String, dynamic> entry in raw.entries) {
    final Object? value = entry.value as Object?;
    converted[entry.key] = value;
  }

  return converted;
}

String? _stringArg(Map<String, Object?> args, String key) {
  final Object? value = args[key];

  return value is String ? value : null;
}

/// Base for tools that delegate to the platform executor.
abstract class DelegatingTool implements NovaTool {
  DelegatingTool({ToolHandler? handler})
    : handler = handler ?? defaultToolHandler;

  final ToolHandler handler;

  @override
  Set<String> get requiredPermissions => const <String>{};

  ToolResult _fromMap(Map<String, Object?> map) {
    final Object? success = map['success'];
    if (success == false) {
      final Object? error = map['error'];

      return ToolResult.fail(error is String ? error : 'Tool $id failed');
    }

    return ToolResult.ok(map);
  }
}

class GetTimeTool extends DelegatingTool {
  GetTimeTool({super.handler});

  @override
  String get id => 'get_time';

  @override
  String get description => 'Get the current time, date, and day of the week.';

  @override
  Map<String, Object> get jsonSchema {
    return const <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    };
  }

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> args,
  ) async {
    final Map<String, Object?> result = await handler(
      id,
      const <String, Object?>{},
    );

    return _fromMap(result);
  }
}

class OpenAppTool extends DelegatingTool {
  OpenAppTool({super.handler});

  @override
  String get id => 'open_app';

  @override
  String get description =>
      'Open an application on the device by package name.';

  @override
  Map<String, Object> get jsonSchema {
    return const <String, Object>{
      'type': 'object',
      'properties': <String, Object>{
        'package': <String, Object>{
          'type': 'string',
          'description': 'Exact Android package name',
        },
      },
      'required': <String>['package'],
    };
  }

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> args,
  ) async {
    final String? package = _stringArg(args, 'package');
    if (package == null || package.isEmpty) {
      return ToolResult.fail('Missing required argument: package');
    }
    final Map<String, Object?> result = await handler(id, <String, Object?>{
      'package': package,
    });

    return _fromMap(result);
  }
}

class SearchWebTool extends DelegatingTool {
  SearchWebTool({super.handler});

  @override
  String get id => 'search_web';

  @override
  String get description => 'Open a web browser and perform a search.';

  @override
  Map<String, Object> get jsonSchema {
    return const <String, Object>{
      'type': 'object',
      'properties': <String, Object>{
        'query': <String, Object>{'type': 'string'},
      },
      'required': <String>['query'],
    };
  }

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> args,
  ) async {
    final String? query = _stringArg(args, 'query');
    if (query == null || query.isEmpty) {
      return ToolResult.fail('Missing required argument: query');
    }
    final Map<String, Object?> result = await handler(id, <String, Object?>{
      'query': query,
    });

    return _fromMap(result);
  }
}

class OpenSettingsTool extends DelegatingTool {
  OpenSettingsTool({super.handler});

  @override
  String get id => 'open_settings';

  @override
  String get description => 'Open the device Settings application.';

  @override
  Map<String, Object> get jsonSchema {
    return const <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    };
  }

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> args,
  ) async {
    final Map<String, Object?> result = await handler(
      id,
      const <String, Object?>{},
    );

    return _fromMap(result);
  }
}

/// Passthrough for remaining legacy tools (alarms, SMS, weather,
/// screenshot, tasks, notes, audio, webfetch, app info, battery, ...).
/// Keeps every legacy tool name resolvable while migrations land one by one.
class PlatformPassthroughTool extends DelegatingTool {
  PlatformPassthroughTool(this.toolId, this.toolDescription, {super.handler});

  final String toolId;
  final String toolDescription;

  @override
  String get id => toolId;

  @override
  String get description => toolDescription;

  @override
  Map<String, Object> get jsonSchema {
    return const <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    };
  }

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> args,
  ) async {
    final Map<String, Object?> result = await handler(id, args);

    return _fromMap(result);
  }
}

/// All legacy tool ids from `NovaTools` with one-line descriptions,
/// so the registry covers 100% of yesterday's surface from day one.
List<PlatformPassthroughTool> legacyPassthroughTools({ToolHandler? handler}) {
  const Map<String, String> legacy = <String, String>{
    'set_alarm': 'Set a device alarm or timer.',
    'cancel_alarm': 'Cancel an existing device alarm.',
    'get_weather': 'Get current weather for a location.',
    'send_sms': 'Send an SMS text message.',
    'take_screenshot': 'Capture a single screenshot of the device screen.',
    'generate_image': 'Generate an image from a text prompt on-device.',
    'force_stop_app': 'Force-stop another app (Shizuku/root required).',
    'open_app_info': 'Open the system App Info page for a package.',
    'open_battery_settings': 'Open the device battery settings.',
    'create_task': 'Create a new to-do task.',
    'list_tasks': 'List pending to-do tasks.',
    'complete_task': 'Mark a to-do task as completed.',
    'create_note': 'Save a note.',
    'search_notes': 'Search through saved notes.',
    'list_notes': 'List recent or pinned notes.',
    'start_audio_recording': 'Start recording audio from the microphone.',
    'stop_audio_recording': 'Stop the current audio recording.',
    'webfetch': 'Fetch and read the content of a web page URL.',
  };

  return <PlatformPassthroughTool>[
    for (final MapEntry<String, String> entry in legacy.entries)
      PlatformPassthroughTool(entry.key, entry.value, handler: handler),
  ];
}

List<NovaTool> allNovaTools({ToolHandler? handler}) {
  return <NovaTool>[
    GetTimeTool(handler: handler),
    OpenAppTool(handler: handler),
    SearchWebTool(handler: handler),
    OpenSettingsTool(handler: handler),
    ...legacyPassthroughTools(handler: handler),
  ];
}

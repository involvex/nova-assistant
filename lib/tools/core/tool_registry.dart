import 'package:nova_assistant/tools/core/nova_tool.dart';
import 'package:nova_assistant/tools/core/tool_context.dart';
import 'package:nova_assistant/tools/core/tool_result.dart';

/// Registry for [NovaTool]s. Single lookup point for router, agents and UI.
class ToolRegistry {
  ToolRegistry._();

  static final Map<String, NovaTool> _tools = <String, NovaTool>{};

  static void register(NovaTool tool) {
    _tools[tool.id] = tool;
  }

  static void registerAll(Iterable<NovaTool> tools) {
    for (final NovaTool tool in tools) {
      register(tool);
    }
  }

  static NovaTool get(String id) {
    final NovaTool? tool = _tools[id];
    if (tool == null) {
      throw StateError('No tool registered for id "$id"');
    }

    return tool;
  }

  static NovaTool? tryGet(String id) => _tools[id];

  static List<String> get ids => List<String>.unmodifiable(_tools.keys);

  static List<NovaTool> get all => List<NovaTool>.unmodifiable(_tools.values);

  static Future<ToolResult> execute(
    String id,
    ToolContext context,
    Map<String, Object?> args,
  ) {
    return get(id).execute(context, args);
  }

  static void clearForTesting() {
    _tools.clear();
  }
}

import 'package:nova_assistant/tools/core/tool_context.dart';
import 'package:nova_assistant/tools/core/tool_result.dart';

/// Assistant actions may only run through this interface (Phase-3 rule).
/// `jsonSchema` follows the same `{type, properties, required}` shape the
/// LLM providers expect, so adapters can translate without core changes.
abstract class NovaTool {
  String get id;

  String get description;

  Map<String, Object> get jsonSchema;

  Set<String> get requiredPermissions;

  Future<ToolResult> execute(ToolContext context, Map<String, Object?> args);
}

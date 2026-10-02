/// Uniform tool result. No `dynamic`: payloads are plain JSON-ish maps.
class ToolResult {
  const ToolResult({
    required this.success,
    this.data = const <String, Object?>{},
    this.error,
  });

  final bool success;
  final Map<String, Object?> data;
  final String? error;

  factory ToolResult.ok([
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    return ToolResult(success: true, data: data);
  }

  factory ToolResult.fail(String error) {
    return ToolResult(success: false, error: error);
  }
}

/// Execution context passed to every tool. Keeps tools decoupled
/// from UI, orchestrator and platform channels.
class ToolContext {
  const ToolContext({required this.sessionId, this.locale = 'de'});

  final String sessionId;
  final String locale;
}

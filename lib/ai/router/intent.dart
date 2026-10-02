/// Classified user intent. Later replaceable by rules + small local model.
enum Intent { local, cloud, tool, vision, automation }

extension IntentX on Intent {
  String get useCase {
    switch (this) {
      case Intent.local:
        return 'simple';
      case Intent.cloud:
        return 'coding';
      case Intent.tool:
        return 'automation';
      case Intent.vision:
        return 'vision';
      case Intent.automation:
        return 'automation';
    }
  }
}

import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/screen/screen_context.dart';

/// Agent request: provider request + routing metadata.
class AgentRequest {
  const AgentRequest({
    required this.intent,
    required this.aiRequest,
    this.screen,
  });

  final Intent intent;
  final AIRequest aiRequest;
  final ScreenContext? screen;
}

/// Single agent. Nova routes automatically via [canHandle].
abstract class NovaAgent {
  String get id;

  String get description;

  bool canHandle(AgentRequest request);

  Stream<String> handle(AgentRequest request, AIProvider provider);
}

/// Thin default: forwards the request to the provider stream.
abstract class ForwardingAgent implements NovaAgent {
  @override
  Stream<String> handle(AgentRequest request, AIProvider provider) {
    return provider.chatStream(request.aiRequest);
  }
}

class AndroidAgent extends ForwardingAgent {
  @override
  String get id => 'android';

  @override
  String get description => 'On-device actions: apps, alarms, settings, SMS.';

  @override
  bool canHandle(AgentRequest request) {
    return request.intent == Intent.tool;
  }
}

class VisionAgent extends ForwardingAgent {
  @override
  String get id => 'vision';

  @override
  String get description => 'Screen awareness: screenshots, OCR, images.';

  @override
  bool canHandle(AgentRequest request) {
    return request.intent == Intent.vision;
  }
}

class CodingAgent extends ForwardingAgent {
  @override
  String get id => 'coding';

  @override
  String get description => 'Code, APK analysis, complex reasoning (cloud).';

  @override
  bool canHandle(AgentRequest request) {
    return request.intent == Intent.cloud;
  }
}

class SearchAgent extends ForwardingAgent {
  @override
  String get id => 'search';

  @override
  String get description => 'Web search and page fetch.';

  @override
  bool canHandle(AgentRequest request) {
    if (request.intent != Intent.tool) {
      return false;
    }
    final String text = request.aiRequest.messages.isEmpty
        ? ''
        : request.aiRequest.messages.last.text.toLowerCase();

    return text.contains('such') ||
        text.contains('search') ||
        text.contains('recherch') ||
        text.contains('finde heraus') ||
        text.contains('link') ||
        text.contains('http');
  }
}

class MemoryAgent extends ForwardingAgent {
  @override
  String get id => 'memory';

  @override
  String get description => 'Recall preferences, notes, past conversations.';

  @override
  bool canHandle(AgentRequest request) {
    if (request.intent != Intent.local) {
      return false;
    }
    final String text = request.aiRequest.messages.isEmpty
        ? ''
        : request.aiRequest.messages.last.text.toLowerCase();

    return text.contains('erinner') ||
        text.contains('remember') ||
        text.contains('notiz') ||
        text.contains('vorliebe') ||
        text.contains('prefer') ||
        text.contains('merke dir');
  }
}

class AutomationAgent extends ForwardingAgent {
  @override
  String get id => 'automation';

  @override
  String get description => 'Routines, macros, recurring workflows.';

  @override
  bool canHandle(AgentRequest request) {
    return request.intent == Intent.automation;
  }
}

class FallbackAgent extends ForwardingAgent {
  @override
  String get id => 'fallback';

  @override
  String get description => 'Catches every request no other agent claims.';

  @override
  bool canHandle(AgentRequest request) => true;
}

List<NovaAgent> defaultAgents() {
  return <NovaAgent>[
    SearchAgent(),
    MemoryAgent(),
    AndroidAgent(),
    VisionAgent(),
    CodingAgent(),
    AutomationAgent(),
    FallbackAgent(),
  ];
}

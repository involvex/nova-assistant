import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/ai/agents/agent.dart';
import 'package:nova_assistant/ai/agents/agent_router.dart';
import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/router/intent.dart';

AgentRequest _probe(Intent intent, String text) {
  return AgentRequest(
    intent: intent,
    aiRequest: AIRequest(
      messages: <ChatTurn>[ChatTurn(role: 'user', text: text)],
    ),
  );
}

void main() {
  group('AgentRouter', () {
    test('routes tool/open to android agent', () {
      final AgentRouter router = AgentRouter();

      expect(router.route(_probe(Intent.tool, 'Öffne Discord')).id, 'android');
    });

    test('routes vision to vision agent', () {
      final AgentRouter router = AgentRouter();

      expect(router.route(_probe(Intent.vision, 'Was sehe ich?')).id, 'vision');
    });

    test('routes cloud to coding agent', () {
      final AgentRouter router = AgentRouter();

      expect(
        router.route(_probe(Intent.cloud, 'Analysiere diese APK')).id,
        'coding',
      );
    });

    test('routes automation to automation agent', () {
      final AgentRouter router = AgentRouter();

      expect(
        router.route(_probe(Intent.automation, 'Automatisiere das')).id,
        'automation',
      );
    });

    test('search query inside tool goes to search agent', () {
      final AgentRouter router = AgentRouter();

      expect(
        router.route(_probe(Intent.tool, 'Such im Web nach Rezepten')).id,
        'search',
      );
    });

    test('fallback catches plain local chat', () {
      final AgentRouter router = AgentRouter();

      expect(
        router.route(_probe(Intent.local, 'Erzähl mir einen Witz')).id,
        'fallback',
      );
    });

    test('memory questions go to memory agent', () {
      final AgentRouter router = AgentRouter();

      expect(
        router.route(_probe(Intent.local, 'Erinnere dich an meine Sprache')).id,
        'memory',
      );
    });
  });
}

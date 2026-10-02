import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/ai/router/intent_router.dart';
import 'package:nova_assistant/ai/router/provider_strategy.dart';
import 'package:nova_assistant/core/config/provider_config.dart';

void main() {
  group('RuleBasedIntentRouter', () {
    const RuleBasedIntentRouter router = RuleBasedIntentRouter();

    test('wie spät ist es -> local', () async {
      expect(await router.route('Wie spät ist es?'), Intent.local);
    });

    test('öffne discord -> tool', () async {
      expect(await router.route('Öffne Discord'), Intent.tool);
    });

    test('analysiere diese apk -> cloud', () async {
      expect(
        await router.route('Analysiere diese APK auf Tracker'),
        Intent.cloud,
      );
    });

    test('was sehe ich auf dem bildschirm -> vision', () async {
      expect(
        await router.route('Was sehe ich auf dem Bildschirm?'),
        Intent.vision,
      );
    });

    test('image attachment forces vision', () async {
      expect(await router.route('Was ist das?', hasImage: true), Intent.vision);
    });

    test('routine einrichten -> automation', () async {
      expect(
        await router.route('Automatisiere meine Morgenroutine'),
        Intent.automation,
      );
    });

    test('code schreiben -> cloud', () async {
      expect(
        await router.route('Schreib mir eine Python-Funktion zum Sortieren'),
        Intent.cloud,
      );
    });

    test('funktioniert-frage bleibt tool, kein cloud-fehlalarm', () async {
      expect(await router.route('Funktioniert mein Wecker?'), Intent.tool);
    });

    test('claude-nennung -> cloud', () async {
      expect(
        await router.route('Frag claude nach einer Zusammenfassung'),
        Intent.cloud,
      );
    });
  });

  group('ProviderStrategy', () {
    test('maps intent to configured provider', () {
      const ProviderConfig config = ProviderConfig(<String, String>{
        'simple': 'local-gemma',
        'coding': 'openrouter',
        'vision': 'local-gemma',
        'automation': 'local-qwen',
        'fallback': 'openrouter',
      });
      final ProviderStrategy strategy = ProviderStrategy(config);

      expect(strategy.providerIdFor(Intent.local), 'local-gemma');
      expect(strategy.providerIdFor(Intent.cloud), 'openrouter');
      expect(strategy.providerIdFor(Intent.vision), 'local-gemma');
      expect(strategy.providerIdFor(Intent.tool), 'local-qwen');
      expect(strategy.providerIdFor(Intent.automation), 'local-qwen');
    });
  });
}

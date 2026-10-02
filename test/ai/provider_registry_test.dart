import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/providers/local_gemma_provider.dart';
import 'package:nova_assistant/ai/providers/local_qwen_provider.dart';
import 'package:nova_assistant/ai/providers/openai_compatible_provider.dart';
import 'package:nova_assistant/ai/providers/provider_capabilities.dart';
import 'package:nova_assistant/ai/providers/provider_registry.dart';
import 'package:nova_assistant/core/config/provider_config.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';

class _FakeProvider implements AIProvider {
  _FakeProvider(this._id);

  final String _id;

  @override
  String get id => _id;

  @override
  Set<ProviderCapability> get capabilities => <ProviderCapability>{
    ProviderCapability.chat,
  };

  @override
  bool get isLocal => true;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<String> chat(AIRequest request) async => 'ok';

  @override
  Stream<String> chatStream(AIRequest request) async* {
    yield 'ok';
  }

  @override
  Future<List<double>> embed(String text) {
    throw UnsupportedError('no embeddings');
  }
}

void main() {
  setUp(() {
    ProviderRegistry.clearForTesting();
  });

  group('ProviderRegistry', () {
    test('registers and resolves by id', () {
      ProviderRegistry.register(_FakeProvider('local-gemma'));

      expect(ProviderRegistry.get('local-gemma').id, 'local-gemma');
      expect(ProviderRegistry.tryGet('missing'), isNull);
    });

    test('unknown id throws', () {
      expect(() => ProviderRegistry.get('nope'), throwsStateError);
    });
  });

  group('Local providers', () {
    test('gemma is local with streaming', () {
      final LocalGemmaProvider provider = LocalGemmaProvider();

      expect(provider.id, 'local-gemma');
      expect(provider.isLocal, isTrue);
      expect(provider.capabilities, contains(ProviderCapability.streaming));
    });

    test('qwen keeps stable id for strategy config', () {
      final LocalQwenProvider provider = LocalQwenProvider();

      expect(provider.id, 'local-qwen');
      expect(provider.isLocal, isTrue);
    });
  });

  group('OpenAI-compatible provider', () {
    test('covers zen / kilo / openrouter via id', () {
      const RemoteInferenceConfig config = RemoteInferenceConfig(
        baseUrl: 'http://localhost:8080',
        modelId: 'test',
      );
      final OpenAiCompatibleProvider zen = OpenAiCompatibleProvider(
        providerId: 'opencode-zen',
        config: config,
      );
      final OpenAiCompatibleProvider kilo = OpenAiCompatibleProvider(
        providerId: 'kilo-gateway',
        config: config,
      );

      expect(zen.isLocal, isFalse);
      expect(kilo.isLocal, isFalse);
      expect(zen.capabilities, contains(ProviderCapability.streaming));
    });
  });

  group('ProviderConfig', () {
    test('parses providers.yaml subset', () {
      const String raw = '''
simple:
  provider: local-gemma
coding:
  provider: openrouter
fallback:
  provider: openrouter
''';
      final ProviderConfig config = ProviderConfig.parse(raw);

      expect(config.providerFor('simple'), 'local-gemma');
      expect(config.providerFor('coding'), 'openrouter');
      expect(config.providerFor('unknown'), 'openrouter');
    });
  });
}

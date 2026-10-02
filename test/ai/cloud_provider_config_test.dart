import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/ai/nova_pipeline.dart';
import 'package:nova_assistant/core/config/cloud_provider_config.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';

void main() {
  group('kCloudProviders', () {
    test('covers the four supported cloud providers, no copilot', () {
      final List<String> ids = <String>[
        for (final CloudProviderEntry entry in kCloudProviders) entry.id,
      ];

      expect(
        ids,
        containsAll(<String>[
          'openrouter',
          'groq',
          'opencode-zen',
          'kilo-gateway',
        ]),
      );
      expect(ids, isNot(contains('copilot')));
    });

    test('kilo is the verified default cloud target', () {
      final CloudProviderEntry kilo = kCloudProviders.firstWhere(
        (CloudProviderEntry e) => e.id == 'kilo-gateway',
      );

      expect(kilo.defaultBaseUrl, 'https://api.kilo.ai/api/gateway');
      expect(kilo.defaultModelId, 'kilo-auto/free');
      expect(kilo.appendV1, isFalse);
    });

    test('zen uses the verified endpoint without /v1 infix', () {
      final CloudProviderEntry zen = kCloudProviders.firstWhere(
        (CloudProviderEntry e) => e.id == 'opencode-zen',
      );

      expect(zen.defaultBaseUrl, 'https://opencode.ai/zen/v1');
      expect(zen.appendV1, isFalse);
    });

    test('prefs keys are namespaced per provider', () {
      const CloudProviderEntry entry = CloudProviderEntry(
        id: 'openrouter',
        displayName: 'OpenRouter',
        defaultBaseUrl: 'https://openrouter.ai/api',
        defaultModelId: 'x',
        help: 'h',
      );

      expect(entry.baseUrlPrefsKey, 'settings_provider_baseurl_openrouter');
      expect(entry.modelPrefsKey, 'settings_provider_model_openrouter');
      expect(entry.tokenPrefsKey, 'settings_provider_token_openrouter');
    });
  });

  group('NovaPipeline.shouldDelegate', () {
    test('flag off never delegates', () {
      expect(
        NovaPipeline.shouldDelegate(
          pipelineEnabled: false,
          providerId: 'openrouter',
        ),
        isFalse,
      );
    });

    test('local providers never delegate', () {
      expect(
        NovaPipeline.shouldDelegate(
          pipelineEnabled: true,
          providerId: 'local-gemma',
        ),
        isFalse,
      );
      expect(
        NovaPipeline.shouldDelegate(
          pipelineEnabled: true,
          providerId: 'local-qwen',
        ),
        isFalse,
      );
    });

    test('cloud providers delegate when enabled', () {
      for (final String id in <String>[
        'openrouter',
        'groq',
        'opencode-zen',
        'kilo-gateway',
        'openai',
      ]) {
        expect(
          NovaPipeline.shouldDelegate(pipelineEnabled: true, providerId: id),
          isTrue,
          reason: id,
        );
      }
    });

    test('orchestrator exposes the same rule', () {
      expect(
        ModelOrchestrator.shouldDelegateToNovaCore(
          pipelineEnabled: true,
          providerId: 'groq',
        ),
        isTrue,
      );
      expect(
        ModelOrchestrator.shouldDelegateToNovaCore(
          pipelineEnabled: true,
          providerId: 'local-gemma',
        ),
        isFalse,
      );
      expect(
        ModelOrchestrator.shouldDelegateToNovaCore(
          pipelineEnabled: false,
          providerId: 'groq',
        ),
        isFalse,
      );
    });
  });

  group('CloudProviderStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('loads defaults when nothing saved', () async {
      const CloudProviderStore store = CloudProviderStore();
      final CloudProviderEntry entry = kCloudProviders[0];

      final CloudProviderValues values = await store.load(entry);

      expect(values.baseUrl, entry.defaultBaseUrl);
      expect(values.modelId, entry.defaultModelId);
      expect(values.apiToken, isNull);
    });

    test('persists base url and model id', () async {
      const CloudProviderStore store = CloudProviderStore();
      final CloudProviderEntry entry = kCloudProviders[1];

      await store.save(
        entry,
        baseUrl: 'https://custom.example/v1',
        modelId: 'custom-model',
      );
      final CloudProviderValues values = await store.load(entry);

      expect(values.baseUrl, 'https://custom.example/v1');
      expect(values.modelId, 'custom-model');
    });

    test('migrates legacy kilo and zen base urls', () async {
      const CloudProviderStore store = CloudProviderStore();
      final CloudProviderEntry kilo = kCloudProviders.firstWhere(
        (CloudProviderEntry e) => e.id == 'kilo-gateway',
      );
      final CloudProviderEntry zen = kCloudProviders.firstWhere(
        (CloudProviderEntry e) => e.id == 'opencode-zen',
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kilo.baseUrlPrefsKey,
        'https://gateway.kilo.ai/api',
      );
      await prefs.setString(zen.baseUrlPrefsKey, 'https://zen.opencode.ai/api');

      final CloudProviderValues kiloValues = await store.load(kilo);
      final CloudProviderValues zenValues = await store.load(zen);

      expect(kiloValues.baseUrl, 'https://api.kilo.ai/api/gateway');
      expect(zenValues.baseUrl, 'https://opencode.ai/zen/v1');
      // Migration persists so it runs exactly once.
      expect(
        prefs.getString(kilo.baseUrlPrefsKey),
        'https://api.kilo.ai/api/gateway',
      );
    });

    test('remote config carries the endpoint style', () async {
      const CloudProviderStore store = CloudProviderStore();
      final CloudProviderEntry kilo = kCloudProviders.firstWhere(
        (CloudProviderEntry e) => e.id == 'kilo-gateway',
      );

      final CloudProviderValues values = await store.load(kilo);
      final config = values.toRemoteConfig();

      expect(
        config.chatCompletionsUri().toString(),
        'https://api.kilo.ai/api/gateway/chat/completions',
      );
    });

    test('validateBaseUrlForCloud accepts https', () {
      expect(
        CloudProviderStore.validateBaseUrlForCloud('https://openrouter.ai/api')
            .scheme,
        'https',
      );
    });

    test('validateBaseUrlForCloud rejects http, file and credentials', () {
      expect(
        () => CloudProviderStore.validateBaseUrlForCloud(
          'http://192.168.1.20:8080',
        ),
        throwsArgumentError,
      );
      expect(
        () => CloudProviderStore.validateBaseUrlForCloud('file:///etc/passwd'),
        throwsArgumentError,
      );
      expect(
        () => CloudProviderStore.validateBaseUrlForCloud(
          'https://user:pass@example.com/v1',
        ),
        throwsArgumentError,
      );
      expect(
        () => CloudProviderStore.validateBaseUrlForCloud(''),
        throwsArgumentError,
      );
    });

    test('save rejects plaintext cloud urls and persists nothing', () async {
      const CloudProviderStore store = CloudProviderStore();
      final CloudProviderEntry entry = kCloudProviders[1];
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await expectLater(
        store.save(entry, baseUrl: 'http://insecure.example/api', modelId: 'm'),
        throwsArgumentError,
      );
      expect(prefs.getString(entry.baseUrlPrefsKey), isNull);
    });
  });
}

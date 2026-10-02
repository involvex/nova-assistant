import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/inference_backend.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteInferenceConfig', () {
    test('builds chat completions URI without trailing slash', () {
      const config = RemoteInferenceConfig(
        baseUrl: 'http://192.168.1.20:8080/',
        modelId: 'qwen',
      );
      expect(
        config.chatCompletionsUri().toString(),
        'http://192.168.1.20:8080/v1/chat/completions',
      );
    });

    test('skips /v1 infix for kilo and zen endpoints', () {
      const kilo = RemoteInferenceConfig(
        baseUrl: 'https://api.kilo.ai/api/gateway',
        modelId: 'kilo-auto/free',
        appendV1: false,
      );
      expect(
        kilo.chatCompletionsUri().toString(),
        'https://api.kilo.ai/api/gateway/chat/completions',
      );
      expect(
        kilo.modelsUri().toString(),
        'https://api.kilo.ai/api/gateway/models',
      );

      const zen = RemoteInferenceConfig(
        baseUrl: 'https://opencode.ai/zen/v1',
        modelId: 'claude-sonnet-4',
        appendV1: false,
      );
      expect(
        zen.chatCompletionsUri().toString(),
        'https://opencode.ai/zen/v1/chat/completions',
      );
      expect(zen.modelsUri().toString(), 'https://opencode.ai/zen/v1/models');
    });

    test('includes bearer token when set', () {
      const config = RemoteInferenceConfig(
        baseUrl: 'http://127.0.0.1:8080',
        modelId: 'local',
        apiToken: 'secret',
      );
      expect(config.headers()['Authorization'], 'Bearer secret');
      expect(config.headers()['Content-Type'], 'application/json');
    });

    test('omits Authorization when token empty', () {
      const config = RemoteInferenceConfig(
        baseUrl: 'http://127.0.0.1:8080',
        modelId: 'local',
        apiToken: '',
      );
      expect(config.headers().containsKey('Authorization'), isFalse);
    });

    test('round-trips prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const config = RemoteInferenceConfig(
        baseUrl: 'http://10.0.0.5:8080',
        modelId: 'llama',
        apiToken: 'tok',
      );
      await config.save(prefs);
      await RemoteInferenceConfig.saveBackend(prefs, InferenceBackend.remote);

      final loaded = await RemoteInferenceConfig.fromPrefsAsync();
      expect(loaded.baseUrl, 'http://10.0.0.5:8080');
      expect(loaded.modelId, 'llama');
      expect(loaded.apiToken, isNull);
      expect(
        RemoteInferenceConfig.backendFromPrefs(prefs),
        InferenceBackend.remote,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/inference_backend.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

      final loaded = RemoteInferenceConfig.fromPrefs(prefs);
      expect(loaded.baseUrl, 'http://10.0.0.5:8080');
      expect(loaded.modelId, 'llama');
      expect(loaded.apiToken, 'tok');
      expect(
        RemoteInferenceConfig.backendFromPrefs(prefs),
        InferenceBackend.remote,
      );
    });
  });
}

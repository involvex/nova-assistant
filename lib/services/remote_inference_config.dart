import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/models/inference_backend.dart';
import 'package:nova_assistant/utils/secure_prefs.dart';

/// Settings for OpenAI-compatible LAN remote inference.
class RemoteInferenceConfig {
  const RemoteInferenceConfig({
    required this.baseUrl,
    required this.modelId,
    this.apiToken,
  });

  final String baseUrl;
  final String modelId;
  final String? apiToken;

  static const backendPrefsKey = 'settings_inference_backend';
  static const baseUrlPrefsKey = 'settings_remote_base_url';
  static const modelIdPrefsKey = 'settings_remote_model_id';
  static const tokenPrefsKey = 'settings_remote_api_token';

  static const defaultBaseUrl = 'http://192.168.1.20:8080';
  static const defaultModelId = 'local-model';

  Uri chatCompletionsUri() {
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');

    return Uri.parse('$trimmed/v1/chat/completions');
  }

  Uri modelsUri() {
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');

    return Uri.parse('$trimmed/v1/models');
  }

  Map<String, String> headers() {
    return {
      'Content-Type': 'application/json',
      if (apiToken != null && apiToken!.isNotEmpty)
        'Authorization': 'Bearer $apiToken',
    };
  }

  factory RemoteInferenceConfig.fromPrefs(SharedPreferences prefs) {
    return RemoteInferenceConfig(
      baseUrl: prefs.getString(baseUrlPrefsKey) ?? defaultBaseUrl,
      modelId: prefs.getString(modelIdPrefsKey) ?? defaultModelId,
      apiToken: null,
    );
  }

  static Future<RemoteInferenceConfig> fromPrefsAsync() async {
    final prefs = await SharedPreferences.getInstance();
    return RemoteInferenceConfig(
      baseUrl: prefs.getString(baseUrlPrefsKey) ?? defaultBaseUrl,
      modelId: prefs.getString(modelIdPrefsKey) ?? defaultModelId,
      apiToken: await SecurePrefs().read(tokenPrefsKey),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(baseUrlPrefsKey, baseUrl);
    await prefs.setString(modelIdPrefsKey, modelId);
    if (apiToken == null || apiToken!.isEmpty) {
      try {
        await SecurePrefs().delete(tokenPrefsKey);
      } catch (e) {
        debugPrint('RemoteInferenceConfig: failed to delete token: $e');
      }
    } else {
      try {
        await SecurePrefs().write(tokenPrefsKey, apiToken!);
      } catch (e) {
        debugPrint('RemoteInferenceConfig: failed to save token: $e');
      }
    }
  }

  static InferenceBackend backendFromPrefs(SharedPreferences prefs) {
    return InferenceBackend.fromPrefsValue(prefs.getString(backendPrefsKey));
  }

  static Future<void> saveBackend(
    SharedPreferences prefs,
    InferenceBackend backend,
  ) async {
    await prefs.setString(backendPrefsKey, backend.prefsValue);
  }

  RemoteInferenceConfig copyWith({
    String? baseUrl,
    String? modelId,
    String? apiToken,
    bool clearToken = false,
  }) {
    return RemoteInferenceConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      modelId: modelId ?? this.modelId,
      apiToken: clearToken ? null : (apiToken ?? this.apiToken),
    );
  }
}

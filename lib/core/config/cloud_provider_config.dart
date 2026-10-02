import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/services/remote_inference_client.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';
import 'package:nova_assistant/utils/secure_prefs.dart';

/// One cloud provider entry (OpenAI-compatible `/v1`).
class CloudProviderEntry {
  const CloudProviderEntry({
    required this.id,
    required this.displayName,
    required this.defaultBaseUrl,
    required this.defaultModelId,
    required this.help,
    this.appendV1 = true,
  });

  final String id;
  final String displayName;
  final String defaultBaseUrl;
  final String defaultModelId;
  final String help;

  /// See [RemoteInferenceConfig.appendV1]. Kilo (`/api/gateway/...`) and
  /// Zen (`/zen/v1/...`) address endpoints directly.
  final bool appendV1;

  String get baseUrlPrefsKey => 'settings_provider_baseurl_$id';

  String get modelPrefsKey => 'settings_provider_model_$id';

  String get tokenPrefsKey => 'settings_provider_token_$id';
}

/// Supported cloud providers. Kilo is the default cloud target.
/// Copilot skipped (no stable API); Opencode Zen + Kilo Gateway are
/// OpenAI-compatible. Base URLs verified live (Feb 2026+).
const List<CloudProviderEntry> kCloudProviders = <CloudProviderEntry>[
  CloudProviderEntry(
    id: 'kilo-gateway',
    displayName: 'Kilo Gateway',
    defaultBaseUrl: 'https://api.kilo.ai/api/gateway',
    defaultModelId: 'kilo-auto/free',
    help: 'Default cloud target. kilo-auto/free needs no credits.',
    appendV1: false,
  ),
  CloudProviderEntry(
    id: 'openrouter',
    displayName: 'OpenRouter',
    defaultBaseUrl: 'https://openrouter.ai/api',
    defaultModelId: 'anthropic/claude-sonnet-4',
    help: 'One key for Claude, GPT, Gemini and open models.',
  ),
  CloudProviderEntry(
    id: 'groq',
    displayName: 'Groq',
    defaultBaseUrl: 'https://api.groq.com/openai',
    defaultModelId: 'llama-3.3-70b-versatile',
    help: 'Ultra-low-latency LPU inference, OpenAI-compatible.',
  ),
  CloudProviderEntry(
    id: 'opencode-zen',
    displayName: 'Opencode Zen',
    defaultBaseUrl: 'https://opencode.ai/zen/v1',
    defaultModelId: 'claude-sonnet-4',
    help: 'Opencode Zen gateway — models via your Zen account.',
    appendV1: false,
  ),
];

/// Legacy base URLs replaced by verified endpoints (auto-migrated on load).
const Map<String, String> kLegacyBaseUrlMigration = <String, String>{
  'https://gateway.kilo.ai/api': 'https://api.kilo.ai/api/gateway',
  'https://zen.opencode.ai/api': 'https://opencode.ai/zen/v1',
};

/// Loaded values for one provider.
class CloudProviderValues {
  const CloudProviderValues({
    required this.baseUrl,
    required this.modelId,
    this.apiToken,
    this.appendV1 = true,
  });

  final String baseUrl;
  final String modelId;
  final String? apiToken;
  final bool appendV1;

  RemoteInferenceConfig toRemoteConfig() {
    return RemoteInferenceConfig(
      baseUrl: baseUrl,
      modelId: modelId,
      apiToken: apiToken,
      appendV1: appendV1,
    );
  }
}

/// Persistence for cloud provider credentials.
/// Base URL + model id live in SharedPreferences (exported in backups);
/// tokens live in secure storage (never backed up, like the LAN token).
class CloudProviderStore {
  const CloudProviderStore();

  /// Validates a cloud base URL: well-formed http(s), no credentials — and
  /// **https only**. API tokens ride the Authorization header, so plain-http
  /// cloud endpoints would leak them on the wire. Plain `http` stays legal
  /// for LAN (`RemoteInferenceConfig`, llama-server/Ollama on the local
  /// network) but never for cloud providers.
  static Uri validateBaseUrlForCloud(String raw) {
    final Uri parsed = RemoteInferenceClient.validateBaseUrl(raw);
    if (parsed.scheme != 'https') {
      throw ArgumentError(
        'Cloud providers require an https base URL (got ${parsed.scheme}) — '
        'plain http is only for LAN (Remote LAN)',
      );
    }
    return parsed;
  }

  Future<CloudProviderValues> load(CloudProviderEntry entry) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String baseUrl =
        prefs.getString(entry.baseUrlPrefsKey) ?? entry.defaultBaseUrl;
    // One-time migration from previously shipped (unverified) endpoints.
    final String? migrated = kLegacyBaseUrlMigration[baseUrl];
    if (migrated != null) {
      baseUrl = migrated;
      await prefs.setString(entry.baseUrlPrefsKey, migrated);
    }
    final String? token = await SecurePrefs().read(entry.tokenPrefsKey);

    return CloudProviderValues(
      baseUrl: baseUrl,
      modelId: prefs.getString(entry.modelPrefsKey) ?? entry.defaultModelId,
      apiToken: token,
      appendV1: entry.appendV1,
    );
  }

  /// Returns true when the token itself was persisted. URL/model are always
  /// persisted; a false result only means secure storage was unavailable and
  /// the token must be re-entered later.
  ///
  /// Throws [ArgumentError] when [baseUrl] is not an https URL — cloud
  /// tokens must never travel over plaintext. Nothing is persisted then.
  Future<bool> save(
    CloudProviderEntry entry, {
    required String baseUrl,
    required String modelId,
    String? apiToken,
  }) async {
    validateBaseUrlForCloud(baseUrl);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(entry.baseUrlPrefsKey, baseUrl);
    await prefs.setString(entry.modelPrefsKey, modelId);
    final String token = apiToken?.trim() ?? '';
    try {
      if (token.isEmpty) {
        await SecurePrefs().delete(entry.tokenPrefsKey);
      } else {
        await SecurePrefs().write(entry.tokenPrefsKey, token);
      }

      return true;
    } catch (e) {
      debugPrint('CloudProviderStore: token save failed for ${entry.id}: $e');

      return false;
    }
  }

  Future<bool> testConnection(CloudProviderValues values) async {
    final RemoteInferenceClient client = RemoteInferenceClient();
    try {
      return await client.testConnection(values.toRemoteConfig());
    } finally {
      client.close();
    }
  }

  /// Fetches the provider's model catalog (`GET <base>/models`).
  /// Returns sorted ids, or throws with a human-readable message.
  Future<List<String>> fetchModels(CloudProviderValues values) async {
    final RemoteInferenceClient client = RemoteInferenceClient();
    try {
      return await client.fetchModels(values.toRemoteConfig());
    } finally {
      client.close();
    }
  }
}

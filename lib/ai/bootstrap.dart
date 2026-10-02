import 'package:flutter/foundation.dart';

import 'package:nova_assistant/ai/agents/agent_router.dart';
import 'package:nova_assistant/ai/nova_core.dart';
import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/providers/local_gemma_provider.dart';
import 'package:nova_assistant/ai/providers/local_qwen_provider.dart';
import 'package:nova_assistant/ai/providers/openai_compatible_provider.dart';
import 'package:nova_assistant/ai/providers/provider_registry.dart';
import 'package:nova_assistant/ai/router/cloud_availability.dart';
import 'package:nova_assistant/ai/router/provider_strategy.dart';
import 'package:nova_assistant/core/config/cloud_provider_config.dart';
import 'package:nova_assistant/core/config/provider_config.dart';
import 'package:nova_assistant/core/connectivity/offline_first_policy.dart';
import 'package:nova_assistant/memory/memory_service_v2.dart';
import 'package:nova_assistant/memory/sqlite_memory.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';
import 'package:nova_assistant/tools/implementations/built_in_tools.dart';
import 'package:nova_assistant/tools/core/tool_registry.dart';
import 'package:nova_assistant/utils/secure_prefs.dart';

/// One-time wiring of the hybrid stack. Called from `main()` alongside the
/// legacy service init; never throws (falls back to safe defaults).
class NovaBootstrap {
  NovaBootstrap._();

  static bool _done = false;
  static NovaCore? _core;

  static NovaCore get core {
    final NovaCore? core = _core;
    if (core == null) {
      throw StateError('NovaBootstrap.ensureInitialized() not called');
    }

    return core;
  }

  static bool get isInitialized => _done;

  static Future<void> _registerCloudProvider({
    required String id,
    required String baseUrl,
    required String modelId,
    String? apiToken,
  }) async {
    if (ProviderRegistry.tryGet(id) != null) {
      return;
    }
    final String? token =
        apiToken ?? await SecurePrefs().read('settings_provider_token_$id');
    ProviderRegistry.register(
      OpenAiCompatibleProvider(
        providerId: id,
        config: RemoteInferenceConfig(
          baseUrl: baseUrl,
          modelId: modelId,
          apiToken: token,
        ),
      ),
    );
  }

  static Future<NovaCore> ensureInitialized() async {
    if (_done && _core != null) {
      return _core!;
    }
    try {
      // 1. Local providers (always available, offline-first).
      if (ProviderRegistry.tryGet('local-gemma') == null) {
        ProviderRegistry.register(LocalGemmaProvider());
      }
      if (ProviderRegistry.tryGet('local-qwen') == null) {
        ProviderRegistry.register(LocalQwenProvider());
      }

      // 2. Cloud providers (OpenAI-compatible). Tokens from secure storage;
      // no network I/O here — reachability is checked lazily per turn.
      // Endpoints/defaults live in kCloudProviders (single source of truth
      // shared with the settings UI); 'openai' follows the LAN settings.
      // Token presence is snapshotted for the smart router.
      final RemoteInferenceConfig lanDefaults =
          await RemoteInferenceConfig.fromPrefsAsync();
      final Map<String, bool> availability = <String, bool>{
        'openai': (lanDefaults.apiToken ?? '').isNotEmpty,
      };
      await _registerCloudProvider(
        id: 'openai',
        baseUrl: lanDefaults.baseUrl,
        modelId: lanDefaults.modelId,
      );
      for (final CloudProviderEntry entry in kCloudProviders) {
        final CloudProviderValues values = await const CloudProviderStore()
            .load(entry);
        await _registerCloudProvider(
          id: entry.id,
          baseUrl: values.baseUrl,
          modelId: values.modelId,
          apiToken: values.apiToken,
        );
        availability[entry.id] = (values.apiToken ?? '').isNotEmpty;
      }
      CloudAvailability.update(availability);

      // 3. Strategy config (build asset, fallback to code defaults).
      ProviderConfig providerConfig;
      try {
        providerConfig = await ProviderConfig.load();
      } catch (e) {
        debugPrint('NovaBootstrap: providers.yaml missing, defaults: $e');
        providerConfig = const ProviderConfig(<String, String>{
          'simple': 'local-gemma',
          'coding': 'kilo-gateway',
          'vision': 'local-gemma',
          'automation': 'local-qwen',
          'fallback': 'kilo-gateway',
        });
      }

      // 4. Tools (full legacy surface via registry).
      if (ToolRegistry.ids.isEmpty) {
        ToolRegistry.registerAll(allNovaTools());
      }

      // 5. Memory: SQLite on-device, in-memory until the DB opens.
      MemoryServiceV2 memory = MemoryServiceV2();
      try {
        final SqliteSessionMemory sqliteSession = SqliteSessionMemory();
        final SqlitePersistentMemory sqlitePersistent =
            SqlitePersistentMemory();
        // Probe write exercises the native plugin only on-device; on
        // unsupported platforms this throws and we keep in-memory.
        await sqliteSession.write('__probe__', 'ok');
        await sqlitePersistent.save('__probe__', 'ok');
        await sqlitePersistent.delete('__probe__');
        memory = MemoryServiceV2(
          session: sqliteSession,
          persistent: sqlitePersistent,
        );
      } catch (e) {
        debugPrint('NovaBootstrap: sqlite unavailable, in-memory: $e');
      }

      _core = NovaCore(
        strategy: ProviderStrategy(providerConfig),
        agents: AgentRouter(),
        offlinePolicy: OfflineFirstPolicy(),
        memory: memory,
      );
      _done = true;

      return _core!;
    } catch (e) {
      debugPrint('NovaBootstrap failed, minimal core: $e');
      if (ProviderRegistry.tryGet('local-gemma') == null) {
        ProviderRegistry.register(LocalGemmaProvider());
      }
      if (ToolRegistry.ids.isEmpty) {
        ToolRegistry.registerAll(allNovaTools());
      }
      _core = NovaCore(memory: MemoryServiceV2());
      _done = true;

      return _core!;
    }
  }

  static void resetForTesting() {
    _done = false;
    _core = null;
  }

  /// Re-reads LAN + cloud provider settings into the registry.
  /// Called after settings saves so turns use fresh URLs/models/tokens
  /// without an app restart. Also snapshots token presence for the smart
  /// router. Never throws; no network I/O.
  static Future<void> refreshProviderConfigs() async {
    try {
      final RemoteInferenceConfig lan =
          await RemoteInferenceConfig.fromPrefsAsync();
      final Map<String, bool> availability = <String, bool>{};
      _updateOpenAiCompatible('openai', lan);
      availability['openai'] = (lan.apiToken ?? '').isNotEmpty;
      const CloudProviderStore store = CloudProviderStore();
      for (final CloudProviderEntry entry in kCloudProviders) {
        final CloudProviderValues values = await store.load(entry);
        _updateOpenAiCompatible(entry.id, values.toRemoteConfig());
        availability[entry.id] = (values.apiToken ?? '').isNotEmpty;
      }
      CloudAvailability.update(availability);
    } catch (e) {
      debugPrint('NovaBootstrap.refreshProviderConfigs failed: $e');
    }
  }

  static void _updateOpenAiCompatible(String id, RemoteInferenceConfig config) {
    final AIProvider? existing = ProviderRegistry.tryGet(id);
    if (existing is OpenAiCompatibleProvider) {
      existing.updateConfig(config);
    }
  }
}

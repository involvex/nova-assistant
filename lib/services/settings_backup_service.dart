import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_assistant/models/adult_mode_policy.dart';
import 'package:nova_assistant/models/agent_identity.dart';
import 'package:nova_assistant/models/assistant_language.dart';
import 'package:nova_assistant/models/assistant_role.dart';
import 'package:nova_assistant/models/inference_backend.dart';
import 'package:nova_assistant/models/prompt_preset.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:nova_assistant/services/export_service.dart';
import 'package:nova_assistant/services/knowledge_base_service.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/prompt_presets_service.dart';
import 'package:nova_assistant/services/remote_inference_config.dart';
import 'package:nova_assistant/services/tts_service.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';

/// Export/import user settings as JSON (no models or secrets).
class SettingsBackupService {
  static SettingsBackupService? _instance;
  static SettingsBackupService get instance =>
      _instance ??= SettingsBackupService._();
  SettingsBackupService._();

  static const schemaVersion = 1;

  Future<Map<String, dynamic>> buildExportMap() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    final userPrefs = await UserPreferencesService.instance.getPreferences();
    final identity = await IdentityService.getIdentity();
    final identityActive = await IdentityService.isActive();

    return {
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': packageInfo.version,
      'settings': {
        'userPreferences': userPrefs.toJson(),
        'assistant': {
          'role':
              prefs.getString('settings_assistant_role') ??
              AssistantRole.helpful.name,
          'language':
              prefs.getString(AssistantLanguage.prefsKey) ??
              AssistantLanguage.match.prefsValue,
          'thinkingMode': prefs.getBool('settings_thinking_mode') ?? false,
          'voiceInput': prefs.getBool('settings_voice_input') ?? true,
          'ttsEnabled': prefs.getBool('settings_tts_enabled') ?? true,
          'autoCapture': prefs.getBool('settings_auto_capture') ?? true,
          'ragMemory': prefs.getBool('settings_rag_memory') ?? false,
          'batteryOptimization':
              prefs.getBool('settings_battery_optimization') ?? true,
          'keepModelWarm': prefs.getBool('settings_keep_model_warm') ?? true,
          'highContext':
              prefs.getBool('settings_high_context') ??
              (kIsWeb || defaultTargetPlatform != TargetPlatform.android),
          'autoCompact': prefs.getBool('settings_auto_compact') ?? true,
          'adultMode': prefs.getBool(AdultModePolicy.prefsKey) ?? false,
          'debugMode': prefs.getBool('settings_debug_mode') ?? false,
          'knowledgeBaseEnabled':
              prefs.getBool(KnowledgeBaseService.enabledPrefsKey) ?? true,
          'inferenceBackend':
              prefs.getString(RemoteInferenceConfig.backendPrefsKey) ??
              InferenceBackend.onDevice.prefsValue,
          'remoteBaseUrl':
              prefs.getString(RemoteInferenceConfig.baseUrlPrefsKey) ??
              RemoteInferenceConfig.defaultBaseUrl,
          'remoteModelId':
              prefs.getString(RemoteInferenceConfig.modelIdPrefsKey) ??
              RemoteInferenceConfig.defaultModelId,
          // Token intentionally omitted from backup — re-enter after import.
        },
        'identity': {'config': identity.toJson(), 'isActive': identityActive},
        'mcp': {
          'servers': McpService.instance.servers
              .map((s) => s.toJson())
              .toList(),
          'tools': McpService.instance.tools.map((t) => t.toJson()).toList(),
          'sources': McpService.instance.sources
              .map((s) => s.toJson())
              .toList(),
        },
        'promptPresets': PromptPresetsService.instance.presets
            .map((p) => p.toJson())
            .toList(),
      },
    };
  }

  Future<String> exportAsJson() async {
    final map = await buildExportMap();

    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Future<void> shareExport() async {
    final json = await exportAsJson();
    await ExportService.instance.shareText(json, 'nova_settings.json');
  }

  Future<SettingsImportResult> importFromPicker() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (result == null) return SettingsImportResult.cancelled();
    if (result.files.isEmpty) {
      return SettingsImportResult.cancelled();
    }

    final file = result.files.first;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      return SettingsImportResult.failure('Could not read the selected file.');
    }

    final text = utf8.decode(bytes);

    return importFromJson(text);
  }

  Future<SettingsImportResult> importFromJson(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return SettingsImportResult.failure('Invalid settings file format.');
      }

      final version = decoded['schemaVersion'] as int? ?? 0;
      if (version != schemaVersion) {
        return SettingsImportResult.failure(
          'Unsupported settings version ($version). '
          'Expected version $schemaVersion.',
        );
      }

      final settings = decoded['settings'] as Map<String, dynamic>?;
      if (settings == null) {
        return SettingsImportResult.failure('Missing settings section.');
      }

      final prefs = await SharedPreferences.getInstance();

      final userPrefsRaw = settings['userPreferences'] as Map<String, dynamic>?;
      if (userPrefsRaw != null) {
        await UserPreferencesService.instance.savePreferences(
          UserPreferences.fromJson(userPrefsRaw),
        );
      }

      final assistant = settings['assistant'] as Map<String, dynamic>?;
      if (assistant != null) {
        await _importAssistantSettings(prefs, assistant);
      }

      final identity = settings['identity'] as Map<String, dynamic>?;
      if (identity != null) {
        final config = identity['config'] as Map<String, dynamic>?;
        if (config != null) {
          await IdentityService.saveIdentity(AgentIdentity.fromJson(config));
        }
        final isActive = identity['isActive'] as bool? ?? false;
        await IdentityService.setActive(isActive);
      }

      final mcp = settings['mcp'] as Map<String, dynamic>?;
      if (mcp != null) {
        await _importMcpSettings(prefs, mcp);
        await McpService.instance.initialize();
      }

      final presetsRaw = settings['promptPresets'] as List<dynamic>?;
      if (presetsRaw != null) {
        final presets = presetsRaw
            .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
            .toList();
        await PromptPresetsService.instance.replaceAll(presets);
      }

      await ModelOrchestrator.refreshSettings();
      await TtsService.instance.setEnabled(
        prefs.getBool('settings_tts_enabled') ?? true,
      );

      return SettingsImportResult.success();
    } catch (e) {
      debugPrint('SettingsBackupService.importFromJson error: $e');

      return SettingsImportResult.failure('Import failed: $e');
    }
  }

  Future<void> _importAssistantSettings(
    SharedPreferences prefs,
    Map<String, dynamic> assistant,
  ) async {
    await prefs.setString(
      'settings_assistant_role',
      assistant['role'] as String? ?? AssistantRole.helpful.name,
    );
    await prefs.setString(
      AssistantLanguage.prefsKey,
      assistant['language'] as String? ?? AssistantLanguage.match.prefsValue,
    );
    await prefs.setBool(
      'settings_thinking_mode',
      assistant['thinkingMode'] as bool? ?? false,
    );
    await prefs.setBool(
      'settings_voice_input',
      assistant['voiceInput'] as bool? ?? true,
    );
    await prefs.setBool(
      'settings_tts_enabled',
      assistant['ttsEnabled'] as bool? ?? true,
    );
    await prefs.setBool(
      'settings_auto_capture',
      assistant['autoCapture'] as bool? ?? true,
    );
    await prefs.setBool(
      'settings_rag_memory',
      assistant['ragMemory'] as bool? ?? false,
    );
    await prefs.setBool(
      'settings_battery_optimization',
      assistant['batteryOptimization'] as bool? ?? true,
    );
    await prefs.setBool(
      'settings_keep_model_warm',
      assistant['keepModelWarm'] as bool? ?? true,
    );
    await prefs.setBool(
      'settings_high_context',
      assistant['highContext'] as bool? ??
          (kIsWeb || defaultTargetPlatform != TargetPlatform.android),
    );
    await prefs.setBool(
      'settings_auto_compact',
      assistant['autoCompact'] as bool? ?? true,
    );
    await prefs.setBool(
      AdultModePolicy.prefsKey,
      assistant['adultMode'] as bool? ?? false,
    );
    await prefs.setBool(
      'settings_debug_mode',
      assistant['debugMode'] as bool? ?? false,
    );
    await prefs.setBool(
      KnowledgeBaseService.enabledPrefsKey,
      assistant['knowledgeBaseEnabled'] as bool? ?? true,
    );
    await prefs.setString(
      RemoteInferenceConfig.backendPrefsKey,
      assistant['inferenceBackend'] as String? ??
          InferenceBackend.onDevice.prefsValue,
    );
    await prefs.setString(
      RemoteInferenceConfig.baseUrlPrefsKey,
      assistant['remoteBaseUrl'] as String? ??
          RemoteInferenceConfig.defaultBaseUrl,
    );
    await prefs.setString(
      RemoteInferenceConfig.modelIdPrefsKey,
      assistant['remoteModelId'] as String? ??
          RemoteInferenceConfig.defaultModelId,
    );
  }

  Future<void> _importMcpSettings(
    SharedPreferences prefs,
    Map<String, dynamic> mcp,
  ) async {
    final servers = mcp['servers'] as List<dynamic>? ?? [];
    final tools = mcp['tools'] as List<dynamic>? ?? [];
    final sources = mcp['sources'] as List<dynamic>? ?? [];

    await prefs.setString('nova_mcp_servers', jsonEncode(servers));
    await prefs.setString('nova_mcp_tools', jsonEncode(tools));
    await prefs.setString('nova_mcp_sources', jsonEncode(sources));
  }
}

class SettingsImportResult {
  final bool success;
  final bool cancelled;
  final String? error;

  const SettingsImportResult._({
    required this.success,
    this.cancelled = false,
    this.error,
  });

  factory SettingsImportResult.success() =>
      const SettingsImportResult._(success: true);

  factory SettingsImportResult.cancelled() =>
      const SettingsImportResult._(success: false, cancelled: true);

  factory SettingsImportResult.failure(String message) =>
      SettingsImportResult._(success: false, error: message);
}

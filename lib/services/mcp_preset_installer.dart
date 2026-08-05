import 'package:nova_assistant/models/external_tool.dart';
import 'package:nova_assistant/models/mcp_preset.dart';
import 'package:nova_assistant/services/mcp_client.dart';
import 'package:nova_assistant/services/mcp_preset_catalog.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:uuid/uuid.dart';

/// Builds [McpServerConfig] / [ExternalTool] instances from catalog presets.
class McpPresetInstaller {
  McpPresetInstaller._();

  static const _uuid = Uuid();

  /// [authMode] is `apiKey`/`bearer` (token fields) or `oauth` (login).
  static Future<void> install(
    McpPreset preset, {
    required McpAuthMode authMode,
    required Map<String, String> secrets,
  }) async {
    if (preset.kind == McpPresetKind.mcp) {
      final token =
          secrets['token'] ?? (secrets.isNotEmpty ? secrets.values.first : '');
      final mode = authMode == McpAuthMode.oauth
          ? McpAuthMode.oauth
          : McpAuthMode.bearer;
      await McpService.instance.installPreset(
        presetId: preset.id,
        title: preset.title,
        isMcp: true,
        url: preset.url,
        transport: preset.transport,
        authMode: mode,
        authToken: token.isNotEmpty ? token : null,
        oauthAuthUrl: preset.oauthAuthUrl,
        oauthTokenUrl: preset.oauthTokenUrl,
        oauthClientId: preset.oauthClientId,
        oauthScope: preset.oauthScope,
      );

      return;
    }

    final headers = <String>[];
    String? apiKey;
    String? apiKeyBodyField;

    for (final field in preset.authFields) {
      final value = secrets[field.key]?.trim() ?? '';
      if (value.isEmpty) continue;
      if (field.bodyField != null) {
        apiKey = value;
        apiKeyBodyField = field.bodyField;
      }
      if (field.headerName != null) {
        var headerVal = value;
        if (field.headerName!.toLowerCase() == 'authorization' &&
            !value.toLowerCase().startsWith('bearer ')) {
          headerVal = 'Bearer $value';
        }
        headers.add('${field.headerName}: $headerVal');
      }
    }

    final tool = ExternalTool(
      id: _uuid.v4(),
      name: preset.httpToolName ?? preset.id.replaceAll('-', '_'),
      description: preset.description,
      type: ExternalToolType.http,
      parameters: Map<String, Object>.from(
        preset.httpParameters ??
            const {'type': 'object', 'properties': <String, Object>{}},
      ),
      config: {
        'url': preset.httpUrl ?? '',
        'method': preset.httpMethod ?? 'POST',
        'headers': headers.join('\n'),
        'presetId': preset.id,
        // ignore: use_null_aware_elements
        if (apiKey != null) 'apiKey': apiKey,
        // ignore: use_null_aware_elements
        if (apiKeyBodyField != null) 'apiKeyBodyField': apiKeyBodyField,
      },
      enabled: true,
    );

    await McpService.instance.installPreset(
      presetId: preset.id,
      title: preset.title,
      isMcp: false,
      httpTool: tool,
    );
  }

  static bool isInstalled(McpPreset preset) {
    if (preset.kind == McpPresetKind.mcp) {
      return McpService.instance.servers.any((s) => s.presetId == preset.id);
    }

    return McpService.instance.tools.any(
      (t) => t.config['presetId'] == preset.id,
    );
  }

  static List<McpPreset> get catalog => McpPresetCatalog.all;
}

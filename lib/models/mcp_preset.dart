import 'package:nova_assistant/services/mcp_client.dart';

enum McpPresetKind { mcp, httpTool }

/// Field shown in the preset configure sheet.
class McpPresetAuthField {
  final String key;
  final String label;
  final bool secret;

  /// When set, value is written as this HTTP header (MCP extraHeaders / HTTP).
  final String? headerName;

  /// When set, value is injected into HTTP JSON body under this key.
  final String? bodyField;

  const McpPresetAuthField({
    required this.key,
    required this.label,
    this.secret = true,
    this.headerName,
    this.bodyField,
  });
}

/// Catalog entry for one-tap MCP / HTTP tool setup.
class McpPreset {
  final String id;
  final String title;
  final String description;
  final String category;
  final McpPresetKind kind;
  final String? docsUrl;

  // MCP
  final String? url;
  final McpTransport transport;
  final McpAuthMode defaultAuthMode;
  final List<McpAuthMode> supportedAuthModes;
  final String? apiKeyHeader;
  final String? oauthAuthUrl;
  final String? oauthTokenUrl;
  final String? oauthClientId;
  final String? oauthScope;
  final String? loginHintUrl;

  // HTTP tool template
  final String? httpUrl;
  final String? httpMethod;
  final String? httpToolName;
  final Map<String, Object>? httpParameters;
  final List<McpPresetAuthField> authFields;

  const McpPreset({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.kind,
    this.docsUrl,
    this.url,
    this.transport = McpTransport.streamableHttp,
    this.defaultAuthMode = McpAuthMode.none,
    this.supportedAuthModes = const [McpAuthMode.none],
    this.apiKeyHeader,
    this.oauthAuthUrl,
    this.oauthTokenUrl,
    this.oauthClientId,
    this.oauthScope,
    this.loginHintUrl,
    this.httpUrl,
    this.httpMethod,
    this.httpToolName,
    this.httpParameters,
    this.authFields = const [],
  });

  bool get supportsLogin =>
      supportedAuthModes.contains(McpAuthMode.oauth) ||
      (loginHintUrl != null && loginHintUrl!.isNotEmpty);

  bool get supportsApiKey =>
      supportedAuthModes.contains(McpAuthMode.bearer) ||
      supportedAuthModes.contains(McpAuthMode.apiKey) ||
      authFields.isNotEmpty;
}

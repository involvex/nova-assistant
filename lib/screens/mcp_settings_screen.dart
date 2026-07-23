// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:nova_assistant/models/external_tool.dart';
import 'package:nova_assistant/models/mcp_preset.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:nova_assistant/services/mcp_client.dart';
import 'package:nova_assistant/services/mcp_oauth.dart';
import 'package:nova_assistant/services/mcp_preset_catalog.dart';
import 'package:nova_assistant/services/mcp_preset_installer.dart';

class McpSettingsScreen extends StatefulWidget {
  const McpSettingsScreen({super.key});

  @override
  State<McpSettingsScreen> createState() => _McpSettingsScreenState();
}

class _McpSettingsScreenState extends State<McpSettingsScreen> {
  final _mcpService = McpService.instance;
  List<ExternalTool> _tools = [];
  List<DataSource> _sources = [];
  List<McpServerConfig> _servers = [];
  StreamSubscription<List<ExternalTool>>? _toolsSub;
  StreamSubscription<List<DataSource>>? _sourcesSub;
  StreamSubscription<List<McpServerConfig>>? _serversSub;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureLoaded());
    _tools = _mcpService.tools;
    _sources = _mcpService.sources;
    _servers = _mcpService.servers;
    _toolsSub = _mcpService.toolsStream.listen((tools) {
      if (mounted) setState(() => _tools = tools);
    });
    _sourcesSub = _mcpService.sourcesStream.listen((sources) {
      if (mounted) setState(() => _sources = sources);
    });
    _serversSub = _mcpService.serversStream.listen((servers) {
      if (mounted) setState(() => _servers = servers);
    });
  }

  Future<void> _ensureLoaded() async {
    await _mcpService.initialize();
    if (!mounted) return;
    setState(() {
      _tools = _mcpService.tools;
      _sources = _mcpService.sources;
      _servers = _mcpService.servers;
    });
  }

  @override
  void dispose() {
    _toolsSub?.cancel();
    _sourcesSub?.cancel();
    _serversSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('External Tools & Data'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      backgroundColor: const Color(0xFF0D0D1A),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Presets', Icons.auto_awesome_outlined),
          Text(
            'One-tap useful MCP / HTTP tools. Enter an API key or use login '
            'when the provider supports it.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...McpPresetCatalog.all.map(_buildPresetCard),
          const SizedBox(height: 24),
          _buildSectionHeader('External Tools', Icons.build_outlined),
          if (_tools.isEmpty) _buildEmptyState('No external tools configured'),
          ..._tools.map(_buildToolTile),
          const SizedBox(height: 8),
          _buildAddButton(
            'Add HTTP Tool',
            () => _showAddToolDialog(ExternalToolType.http),
          ),
          _buildAddButton(
            'Add MCP Server Tool',
            () => _showAddToolDialog(ExternalToolType.mcp),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Mcp Servers', Icons.dns_outlined),
          if (_servers.isEmpty) _buildEmptyState('No MCP servers configured'),
          ..._servers.map(_buildServerTile),
          const SizedBox(height: 8),
          _buildAddButton('Add MCP Server', _showAddServerDialog),
          const SizedBox(height: 24),
          _buildSectionHeader('Data Sources', Icons.storage_outlined),
          if (_sources.isEmpty) _buildEmptyState('No data sources configured'),
          ..._sources.map(_buildSourceTile),
          const SizedBox(height: 8),
          _buildAddButton(
            'Add File Source',
            () => _showAddSourceDialog(SourceType.file),
          ),
          _buildAddButton(
            'Add URL Source',
            () => _showAddSourceDialog(SourceType.url),
          ),
          _buildAddButton(
            'Add API Source',
            () => _showAddSourceDialog(SourceType.api),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(McpPreset preset) {
    final installed = McpPresetInstaller.isInstalled(preset);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1A1A2E),
      child: ListTile(
        leading: Icon(
          preset.kind == McpPresetKind.mcp ? Icons.hub_outlined : Icons.http,
          color: const Color(0xFF6C63FF),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                preset.title,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            if (installed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Installed',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${preset.category} · ${preset.description}',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: () => _showPresetConfigureSheet(preset),
      ),
    );
  }

  Future<void> _showPresetConfigureSheet(McpPreset preset) async {
    var authMode = preset.defaultAuthMode;
    if (authMode == McpAuthMode.none && preset.supportsApiKey) {
      authMode = preset.supportedAuthModes.contains(McpAuthMode.bearer)
          ? McpAuthMode.bearer
          : McpAuthMode.apiKey;
    }
    final controllers = <String, TextEditingController>{
      for (final f in preset.authFields) f.key: TextEditingController(),
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preset.description,
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    if (preset.supportsApiKey && preset.supportsLogin) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('API key'),
                            selected: authMode != McpAuthMode.oauth,
                            onSelected: (_) => setModal(() {
                              authMode =
                                  preset.supportedAuthModes.contains(
                                    McpAuthMode.bearer,
                                  )
                                  ? McpAuthMode.bearer
                                  : McpAuthMode.apiKey;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text('Login'),
                            selected: authMode == McpAuthMode.oauth,
                            onSelected: (_) => setModal(() {
                              authMode = McpAuthMode.oauth;
                            }),
                          ),
                        ],
                      ),
                    ],
                    if (authMode == McpAuthMode.oauth) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Open the provider login / token page, then paste the '
                        'access token below. After install, use Authorize on '
                        'the server menu if OAuth endpoints are configured.',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                      if (preset.loginHintUrl != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(preset.loginHintUrl!);
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open login / tokens'),
                        ),
                      ],
                    ],
                    ...preset.authFields.map((field) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: controllers[field.key],
                          obscureText: field.secret,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: field.label,
                            labelStyle: TextStyle(color: Colors.grey.shade400),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF6C63FF)),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (preset.docsUrl != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () async {
                          await launchUrl(
                            Uri.parse(preset.docsUrl!),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: const Text('Documentation'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        final secrets = <String, String>{
                          for (final e in controllers.entries)
                            e.key: e.value.text.trim(),
                        };
                        await McpPresetInstaller.install(
                          preset,
                          authMode: authMode,
                          secrets: secrets,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              McpPresetInstaller.isInstalled(preset)
                                  ? '${preset.title} installed'
                                  : 'Installed ${preset.title}',
                            ),
                          ),
                        );
                        if (preset.kind == McpPresetKind.mcp) {
                          final matches = _mcpService.servers
                              .where((s) => s.presetId == preset.id)
                              .toList();
                          final server = matches.isEmpty ? null : matches.first;
                          if (server != null &&
                              (secrets['token']?.isNotEmpty ?? false)) {
                            final ok = await _mcpService.connectServer(
                              server.id,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Connected to ${preset.title}'
                                      : (_mcpService.lastConnectError ??
                                            'Connect failed — try Connect from the server menu'),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                      ),
                      child: Text(
                        McpPresetInstaller.isInstalled(preset)
                            ? 'Update'
                            : 'Install',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Text(message, style: TextStyle(color: Colors.grey.shade400)),
      ),
    );
  }

  Widget _buildToolTile(ExternalTool tool) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1A1A2E),
      child: ListTile(
        leading: Icon(
          tool.type == ExternalToolType.http ? Icons.http : Icons.dns,
          color: const Color(0xFF6C63FF),
        ),
        title: Text(tool.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          tool.description,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: tool.enabled,
              onChanged: (value) {
                _mcpService.updateTool(tool.copyWith(enabled: value));
              },
              activeColor: const Color(0xFF6C63FF),
            ),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _showEditToolDialog(tool);
                if (action == 'delete') _deleteTool(tool);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerTile(McpServerConfig server) {
    return Card(
      color: const Color(0xFF1A1A2E),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.dns_outlined,
          color: server.connected ? Colors.green : Colors.grey,
        ),
        title: Text(server.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '${server.transport.name} · '
          '${server.connected ? 'Connected' : 'Disconnected'}',
          style: TextStyle(
            color: server.connected ? Colors.green : Colors.grey,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: server.enabled,
              onChanged: (value) {
                _mcpService.toggleServer(server.id, value);
              },
              activeColor: const Color(0xFF6C63FF),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'connect') {
                  final ok = await _mcpService.connectServer(server.id);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Connected to ${server.name}'
                            : (_mcpService.lastConnectError ??
                                  'Failed to connect to ${server.name}'),
                      ),
                      backgroundColor: ok ? Colors.green[700] : Colors.red[700],
                      duration: Duration(seconds: ok ? 3 : 8),
                    ),
                  );
                } else if (value == 'disconnect') {
                  await _mcpService.disconnectServer(server.id);
                } else if (value == 'oauth') {
                  await _authorizeServer(server);
                } else if (value == 'delete') {
                  _showDeleteServerConfirm(server);
                }
              },
              itemBuilder: (context) => [
                if (!server.connected)
                  const PopupMenuItem(value: 'connect', child: Text('Connect')),
                if (server.connected)
                  const PopupMenuItem(
                    value: 'disconnect',
                    child: Text('Disconnect'),
                  ),
                if (server.hasOAuth)
                  const PopupMenuItem(
                    value: 'oauth',
                    child: Text('Authorize (OAuth)'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _authorizeServer(McpServerConfig server) async {
    if (!server.hasOAuth) return;
    final oauth = McpOAuthService.instance;
    final pkce = oauth.createPkce();
    await oauth.savePkceVerifier(server.id, pkce.verifier);
    final opened = await oauth.openAuthorizationUrl(
      authorizationEndpoint: server.oauthAuthUrl!,
      clientId: server.oauthClientId!,
      redirectUri: server.oauthRedirectUri ?? 'nova://mcp/oauth',
      codeChallenge: pkce.challenge,
      scope: server.oauthScope,
      state: server.id,
    );
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open authorization URL')),
      );

      return;
    }

    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Paste OAuth code',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: codeController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Authorization code from redirect',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, codeController.text.trim()),
            child: const Text('Exchange'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;

    final verifier = await oauth.loadPkceVerifier(server.id);
    if (verifier == null) return;
    final tokens = await oauth.exchangeCode(
      tokenEndpoint: server.oauthTokenUrl!,
      clientId: server.oauthClientId!,
      redirectUri: server.oauthRedirectUri ?? 'nova://mcp/oauth',
      code: code,
      codeVerifier: verifier,
    );
    if (!mounted) return;
    if (tokens == null || tokens['access_token'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OAuth token exchange failed')),
      );

      return;
    }
    await oauth.saveTokens(
      serverId: server.id,
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String?,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OAuth token saved — you can Connect now')),
    );
  }

  void _showDeleteServerConfirm(McpServerConfig server) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Delete Server',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove "${server.name}" and its discovered tools?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _mcpService.removeServer(server.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddServerDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final tokenController = TextEditingController();
    final commandController = TextEditingController();
    final oauthAuthController = TextEditingController();
    final oauthTokenController = TextEditingController();
    final oauthClientController = TextEditingController();
    final oauthRedirectController = TextEditingController(
      text: 'nova://mcp/oauth',
    );
    final oauthScopeController = TextEditingController();
    McpTransport transport = McpTransport.streamableHttp;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'Add MCP Server',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogTextField(nameController, 'Server name'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _transportChip(
                      label: 'Streamable HTTP',
                      selected: transport == McpTransport.streamableHttp,
                      onTap: () => setDialogState(
                        () => transport = McpTransport.streamableHttp,
                      ),
                    ),
                    _transportChip(
                      label: 'HTTP/SSE',
                      selected: transport == McpTransport.httpSse,
                      onTap: () => setDialogState(
                        () => transport = McpTransport.httpSse,
                      ),
                    ),
                    _transportChip(
                      label: 'Stdio',
                      selected: transport == McpTransport.stdio,
                      onTap: () =>
                          setDialogState(() => transport = McpTransport.stdio),
                    ),
                  ],
                ),
                if (transport != McpTransport.stdio) ...[
                  const SizedBox(height: 12),
                  _dialogTextField(urlController, 'Server URL'),
                  const SizedBox(height: 12),
                  _dialogTextField(tokenController, 'Bearer token (optional)'),
                  const SizedBox(height: 12),
                  Text(
                    'OAuth (optional)',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _dialogTextField(oauthAuthController, 'Authorization URL'),
                  const SizedBox(height: 8),
                  _dialogTextField(oauthTokenController, 'Token URL'),
                  const SizedBox(height: 8),
                  _dialogTextField(oauthClientController, 'Client ID'),
                  const SizedBox(height: 8),
                  _dialogTextField(oauthRedirectController, 'Redirect URI'),
                  const SizedBox(height: 8),
                  _dialogTextField(oauthScopeController, 'Scope (optional)'),
                ] else ...[
                  const SizedBox(height: 12),
                  _dialogTextField(commandController, 'Command (e.g. npx)'),
                  const SizedBox(height: 12),
                  _dialogTextField(
                    urlController,
                    'Arguments (comma-separated)',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.isEmpty) return;

                final args = transport == McpTransport.stdio
                    ? urlController.text
                          .split(',')
                          .map((a) => a.trim())
                          .where((a) => a.isNotEmpty)
                          .toList()
                    : <String>[];

                final server = McpServerConfig(
                  id: const Uuid().v4(),
                  name: nameController.text.trim(),
                  url: urlController.text.trim(),
                  transport: transport,
                  authToken: tokenController.text.isEmpty
                      ? null
                      : tokenController.text.trim(),
                  command: transport == McpTransport.stdio
                      ? commandController.text.trim()
                      : null,
                  args: args,
                  oauthAuthUrl: oauthAuthController.text.trim().isEmpty
                      ? null
                      : oauthAuthController.text.trim(),
                  oauthTokenUrl: oauthTokenController.text.trim().isEmpty
                      ? null
                      : oauthTokenController.text.trim(),
                  oauthClientId: oauthClientController.text.trim().isEmpty
                      ? null
                      : oauthClientController.text.trim(),
                  oauthRedirectUri: oauthRedirectController.text.trim().isEmpty
                      ? null
                      : oauthRedirectController.text.trim(),
                  oauthScope: oauthScopeController.text.trim().isEmpty
                      ? null
                      : oauthScopeController.text.trim(),
                );

                _mcpService.addServer(server);
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transportChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6C63FF).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : Colors.grey[700]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF6C63FF) : Colors.grey,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceTile(DataSource source) {
    final icon = switch (source.type) {
      SourceType.file => Icons.insert_drive_file_outlined,
      SourceType.url => Icons.link,
      SourceType.api => Icons.api,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1A1A2E),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF6C63FF)),
        title: Text(source.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          source.description,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: source.enabled,
              onChanged: (value) {
                _mcpService.updateSource(source.copyWith(enabled: value));
              },
              activeColor: const Color(0xFF6C63FF),
            ),
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _showEditSourceDialog(source);
                if (action == 'delete') _deleteSource(source);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6C63FF),
          side: const BorderSide(color: Color(0xFF6C63FF)),
          minimumSize: const Size(double.infinity, 44),
        ),
      ),
    );
  }

  void _showAddToolDialog(ExternalToolType type) {
    _showToolDialog(type: type);
  }

  void _showEditToolDialog(ExternalTool tool) {
    _showToolDialog(tool: tool, type: tool.type);
  }

  void _showToolDialog({ExternalTool? tool, required ExternalToolType type}) {
    final nameController = TextEditingController(text: tool?.name ?? '');
    final descController = TextEditingController(text: tool?.description ?? '');
    final urlController = TextEditingController(
      text: tool?.config['url'] ?? '',
    );
    final methodController = TextEditingController(
      text: tool?.config['method'] ?? 'GET',
    );
    final serverUrlController = TextEditingController(
      text: tool?.config['serverUrl'] ?? '',
    );
    final tokenController = TextEditingController(
      text: tool?.config['token'] ?? '',
    );
    final paramsController = TextEditingController(
      text: tool != null ? _prettyJson(tool.parameters) : '{\n  \n}',
    );

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          tool != null
              ? 'Edit Tool'
              : (type == ExternalToolType.http
                    ? 'Add HTTP Tool'
                    : 'Add MCP Tool'),
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(nameController, 'Tool name (snake_case)'),
              const SizedBox(height: 12),
              _dialogTextField(descController, 'Description'),
              const SizedBox(height: 12),
              if (type == ExternalToolType.http) ...[
                _dialogTextField(urlController, 'Endpoint URL'),
                const SizedBox(height: 12),
                _dialogTextField(methodController, 'HTTP method (GET/POST)'),
              ] else ...[
                _dialogTextField(serverUrlController, 'MCP Server URL'),
                const SizedBox(height: 12),
                _dialogTextField(tokenController, 'Auth token (optional)'),
              ],
              const SizedBox(height: 12),
              _dialogTextField(
                paramsController,
                'Parameters JSON',
                maxLines: 6,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final config = <String, String>{};
              if (type == ExternalToolType.http) {
                config['url'] = urlController.text;
                config['method'] = methodController.text;
              } else {
                config['serverUrl'] = serverUrlController.text;
                config['token'] = tokenController.text;
              }

              final params = _parseJson(paramsController.text);

              final newTool = ExternalTool(
                id: tool?.id ?? const Uuid().v4(),
                name: nameController.text,
                description: descController.text,
                type: type,
                parameters: params,
                config: config,
                enabled: tool?.enabled ?? true,
                createdAt: tool?.createdAt,
              );

              if (tool != null) {
                _mcpService.updateTool(newTool);
              } else {
                _mcpService.addTool(newTool);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog(SourceType type) {
    _showSourceDialog(type: type);
  }

  void _showEditSourceDialog(DataSource source) {
    _showSourceDialog(source: source, type: source.type);
  }

  void _showSourceDialog({DataSource? source, required SourceType type}) {
    final nameController = TextEditingController(text: source?.name ?? '');
    final descController = TextEditingController(
      text: source?.description ?? '',
    );
    final pathController = TextEditingController(
      text: source?.config['path'] ?? '',
    );
    final urlController = TextEditingController(
      text: source?.config['url'] ?? '',
    );
    final tokenController = TextEditingController(
      text: source?.config['token'] ?? '',
    );
    final extractPathController = TextEditingController(
      text: source?.config['extractPath'] ?? '',
    );
    final maxLengthController = TextEditingController(
      text: source?.config['maxLength'] ?? '',
    );

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          source != null ? 'Edit Source' : 'Add Data Source',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(nameController, 'Name'),
              const SizedBox(height: 12),
              _dialogTextField(descController, 'Description'),
              const SizedBox(height: 12),
              if (type == SourceType.file)
                _dialogTextField(pathController, 'File path'),
              if (type == SourceType.url || type == SourceType.api)
                _dialogTextField(urlController, 'URL'),
              if (type == SourceType.api) ...[
                const SizedBox(height: 12),
                _dialogTextField(tokenController, 'Auth token (optional)'),
                const SizedBox(height: 12),
                _dialogTextField(
                  extractPathController,
                  'JSON extract path (optional)',
                ),
              ],
              if (type == SourceType.file) ...[
                const SizedBox(height: 12),
                _dialogTextField(maxLengthController, 'Max chars (optional)'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final config = <String, String>{};
              if (type == SourceType.file) {
                config['path'] = pathController.text;
                if (maxLengthController.text.isNotEmpty) {
                  config['maxLength'] = maxLengthController.text;
                }
              } else {
                config['url'] = urlController.text;
                if (tokenController.text.isNotEmpty) {
                  config['token'] = tokenController.text;
                }
                if (extractPathController.text.isNotEmpty) {
                  config['extractPath'] = extractPathController.text;
                }
              }

              final newSource = DataSource(
                id: source?.id ?? const Uuid().v4(),
                name: nameController.text,
                description: descController.text,
                type: type,
                config: config,
                enabled: source?.enabled ?? true,
                createdAt: source?.createdAt,
              );

              if (source != null) {
                _mcpService.updateSource(newSource);
              } else {
                _mcpService.addSource(newSource);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _dialogTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade500),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  void _deleteTool(ExternalTool tool) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Tool', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${tool.name}"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _mcpService.removeTool(tool.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteSource(DataSource source) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Delete Source',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${source.name}"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _mcpService.removeSource(source.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _prettyJson(Map<String, Object> json) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }

  Map<String, Object> _parseJson(String text) {
    try {
      final decoded = Map<String, Object>.from(jsonDecode(text) as Map);
      return decoded;
    } catch (_) {
      return {'type': 'object', 'properties': <String, Object>{}};
    }
  }
}

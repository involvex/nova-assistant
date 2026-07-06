import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:nova_assistant/models/external_tool.dart';
import 'package:nova_assistant/services/mcp_service.dart';

class McpSettingsScreen extends StatefulWidget {
  const McpSettingsScreen({super.key});

  @override
  State<McpSettingsScreen> createState() => _McpSettingsScreenState();
}

class _McpSettingsScreenState extends State<McpSettingsScreen> {
  final _mcpService = McpService.instance;
  List<ExternalTool> _tools = [];
  List<DataSource> _sources = [];

  @override
  void initState() {
    super.initState();
    _tools = _mcpService.tools;
    _sources = _mcpService.sources;
    _mcpService.toolsStream.listen((tools) {
      if (mounted) setState(() => _tools = tools);
    });
    _mcpService.sourcesStream.listen((sources) {
      if (mounted) setState(() => _sources = sources);
    });
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

    showDialog(
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

    showDialog(
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
    showDialog(
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
    showDialog(
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

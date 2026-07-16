import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:nova_assistant/models/external_tool.dart';
import 'package:nova_assistant/services/mcp_client.dart';

class McpService {
  static McpService? _instance;
  static McpService get instance => _instance ??= McpService._();
  McpService._();

  static const _prefsKey = 'nova_mcp_tools';
  static const _sourcesKey = 'nova_mcp_sources';
  static const _serversKey = 'nova_mcp_servers';
  static const _uuid = Uuid();

  final _toolsController = StreamController<List<ExternalTool>>.broadcast();
  Stream<List<ExternalTool>> get toolsStream => _toolsController.stream;

  final _sourcesController = StreamController<List<DataSource>>.broadcast();
  Stream<List<DataSource>> get sourcesStream => _sourcesController.stream;

  final _serversController =
      StreamController<List<McpServerConfig>>.broadcast();
  Stream<List<McpServerConfig>> get serversStream => _serversController.stream;

  List<ExternalTool> _tools = [];
  List<DataSource> _sources = [];
  List<McpServerConfig> _servers = [];
  final Map<String, McpClient> _clients = {};

  List<ExternalTool> get tools => List.unmodifiable(_tools);
  List<DataSource> get sources => List.unmodifiable(_sources);
  List<McpServerConfig> get servers => List.unmodifiable(_servers);

  final Map<ExternalToolType, ExternalToolProvider> _providers = {
    ExternalToolType.http: HttpToolProvider(),
    ExternalToolType.mcp: McpToolProvider(),
  };

  Future<void> initialize() async {
    await _loadTools();
    await _loadSources();
    await _loadServers();
    debugPrint(
      'MCP service initialized with ${_tools.length} tools, ${_sources.length} sources, ${_servers.length} servers',
    );
  }

  Future<void> _loadTools() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null) {
        final list = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
        _tools = list.map(ExternalTool.fromJson).toList();
        _toolsController.add(_tools);
      }
    } catch (e) {
      debugPrint('Failed to load MCP tools: $e');
    }
  }

  Future<void> _loadSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_sourcesKey);
      if (jsonStr != null) {
        final list = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
        _sources = list.map(DataSource.fromJson).toList();
        _sourcesController.add(_sources);
      }
    } catch (e) {
      debugPrint('Failed to load MCP sources: $e');
    }
  }

  Future<void> _saveTools() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_tools.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, json);
      _toolsController.add(_tools);
    } catch (e) {
      debugPrint('Failed to save MCP tools: $e');
    }
  }

  Future<void> _saveSources() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_sources.map((e) => e.toJson()).toList());
      await prefs.setString(_sourcesKey, json);
      _sourcesController.add(_sources);
    } catch (e) {
      debugPrint('Failed to save MCP sources: $e');
    }
  }

  // --- MCP Server Management ---

  Future<void> _loadServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_serversKey);
      if (jsonStr != null) {
        final list = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
        _servers = list.map(McpServerConfig.fromJson).toList();
        _serversController.add(_servers);
      }
    } catch (e) {
      debugPrint('Failed to load MCP servers: $e');
    }
  }

  Future<void> _saveServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_servers.map((e) => e.toJson()).toList());
      await prefs.setString(_serversKey, json);
      _serversController.add(_servers);
    } catch (e) {
      debugPrint('Failed to save MCP servers: $e');
    }
  }

  Future<void> addServer(McpServerConfig server) async {
    _servers.add(server);
    await _saveServers();
  }

  Future<void> removeServer(String serverId) async {
    await disconnectServer(serverId);
    _servers.removeWhere((s) => s.id == serverId);
    // Remove tools from this server
    _tools.removeWhere((t) => t.config['serverId'] == serverId);
    await _saveServers();
    await _saveTools();
  }

  Future<void> toggleServer(String serverId, bool enabled) async {
    final index = _servers.indexWhere((s) => s.id == serverId);
    if (index >= 0) {
      _servers[index].enabled = enabled;
      if (!enabled) {
        await disconnectServer(serverId);
      }
      await _saveServers();
    }
  }

  McpServerConfig? getServer(String serverId) {
    try {
      return _servers.firstWhere((s) => s.id == serverId);
    } catch (_) {
      return null;
    }
  }

  Future<bool> connectServer(String serverId) async {
    final config = getServer(serverId);
    if (config == null || !config.enabled) return false;

    // Disconnect existing client
    await disconnectServer(serverId);

    final client = McpClient(config);
    final connected = await client.connect();

    if (connected) {
      _clients[serverId] = client;
      await _discoverTools(client);
      debugPrint('Connected to MCP server: ${config.name}');
      return true;
    }

    debugPrint('Failed to connect to MCP server: ${config.name}');
    return false;
  }

  Future<void> disconnectServer(String serverId) async {
    final client = _clients.remove(serverId);
    if (client != null) {
      await client.disconnect();
      // Remove tools from this server
      _tools.removeWhere((t) => t.config['serverId'] == serverId);
      await _saveTools();
    }
  }

  Future<void> _discoverTools(McpClient client) async {
    final mcpTools = await client.listTools();

    for (final toolInfo in mcpTools) {
      // Check if tool already exists
      final existing = _tools.where(
        (t) =>
            t.name == toolInfo.name && t.config['serverId'] == client.config.id,
      );

      if (existing.isEmpty) {
        final externalTool = ExternalTool(
          id: _uuid.v4(),
          name: toolInfo.name,
          description: toolInfo.description,
          type: ExternalToolType.mcp,
          parameters: Map<String, Object>.from(toolInfo.inputSchema),
          config: {
            'serverId': client.config.id,
            'serverUrl': client.config.url,
          },
          enabled: true,
        );
        _tools.add(externalTool);
      }
    }

    await _saveTools();
  }

  Future<Map<String, dynamic>?> executeMcpTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final client = _clients[serverId];
    if (client == null) return null;

    return client.callTool(toolName, args);
  }

  Future<void> addTool(ExternalTool tool) async {
    _tools.add(tool);
    await _saveTools();
  }

  Future<void> updateTool(ExternalTool tool) async {
    final index = _tools.indexWhere((t) => t.id == tool.id);
    if (index >= 0) {
      _tools[index] = tool;
      await _saveTools();
    }
  }

  Future<void> removeTool(String toolId) async {
    _tools.removeWhere((t) => t.id == toolId);
    await _saveTools();
  }

  ExternalTool? getTool(String name) {
    try {
      return _tools.firstWhere((t) => t.name == name && t.enabled);
    } catch (_) {
      return null;
    }
  }

  List<gemma.Tool> get enabledTools {
    return _tools.where((t) => t.enabled).map((t) => t.toTool()).toList();
  }

  Future<ExternalToolResult> executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final tool = getTool(toolName);
    if (tool == null) {
      return ExternalToolResult(
        success: false,
        error: 'Tool not found or disabled: $toolName',
      );
    }

    final provider = _providers[tool.type];
    if (provider == null) {
      return ExternalToolResult(
        success: false,
        error: 'No provider for tool type: ${tool.type}',
      );
    }

    return provider.execute(tool, args);
  }

  Future<void> addSource(DataSource source) async {
    _sources.add(source);
    await _saveSources();
  }

  Future<void> updateSource(DataSource source) async {
    final index = _sources.indexWhere((s) => s.id == source.id);
    if (index >= 0) {
      _sources[index] = source;
      await _saveSources();
    }
  }

  Future<void> removeSource(String sourceId) async {
    _sources.removeWhere((s) => s.id == sourceId);
    await _saveSources();
  }

  Future<String> fetchSourceContext(String sourceId) async {
    final source = _sources.firstWhere(
      (s) => s.id == sourceId,
      orElse: () => throw Exception('Source not found: $sourceId'),
    );

    if (!source.enabled) {
      return '';
    }

    try {
      switch (source.type) {
        case SourceType.file:
          return await _readFileSource(source);
        case SourceType.url:
          return await _fetchUrlSource(source);
        case SourceType.api:
          return await _fetchApiSource(source);
      }
    } catch (e) {
      debugPrint('Failed to fetch source ${source.name}: $e');
      return '[Error fetching ${source.name}: $e]';
    }
  }

  Future<String> _readFileSource(DataSource source) async {
    final path = source.config['path'] ?? '';
    if (path.isEmpty) return '';

    final file = File(path);
    if (!await file.exists()) {
      return '[File not found: $path]';
    }

    final content = await file.readAsString();
    if (source.config['maxLength'] != null) {
      final maxLength = int.parse(source.config['maxLength']!);
      if (content.length > maxLength) {
        return '${content.substring(0, maxLength)}... [truncated]';
      }
    }
    return content;
  }

  Future<String> _fetchUrlSource(DataSource source) async {
    final url = source.config['url'] ?? '';
    if (url.isEmpty) return '';

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      } else {
        return '[HTTP ${response.statusCode}]';
      }
    } finally {
      client.close();
    }
  }

  Future<String> _fetchApiSource(DataSource source) async {
    final url = source.config['url'] ?? '';
    final token = source.config['token'] ?? '';
    if (url.isEmpty) return '';

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final json = jsonDecode(body);
          return _extractRelevantContent(json, source.config['extractPath']);
        } catch (_) {
          return body;
        }
      } else {
        return '[HTTP ${response.statusCode}]';
      }
    } finally {
      client.close();
    }
  }

  String _extractRelevantContent(dynamic json, String? extractPath) {
    if (extractPath == null || extractPath.isEmpty) {
      return jsonEncode(json);
    }

    dynamic current = json;
    for (final part in extractPath.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else if (current is List) {
        final index = int.tryParse(part);
        if (index != null && index < current.length) {
          current = current[index];
        } else {
          return jsonEncode(json);
        }
      } else {
        return jsonEncode(json);
      }
    }

    if (current is String) return current;
    return jsonEncode(current);
  }

  /// Dispose resources
  Future<void> dispose() async {
    for (final client in _clients.values) {
      await client.disconnect();
    }
    _clients.clear();
    await _toolsController.close();
    await _sourcesController.close();
    await _serversController.close();
  }
}

enum SourceType { file, url, api }

class DataSource {
  final String id;
  final String name;
  final String description;
  final SourceType type;
  final Map<String, String> config;
  final bool enabled;
  final DateTime createdAt;

  DataSource({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.config = const {},
    this.enabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  DataSource copyWith({
    String? name,
    String? description,
    SourceType? type,
    Map<String, String>? config,
    bool? enabled,
  }) {
    return DataSource(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      config: config ?? this.config,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'config': config,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DataSource.fromJson(Map<String, dynamic> json) {
    return DataSource(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      type: SourceType.values.firstWhere((t) => t.name == json['type']),
      config: Map<String, String>.from(json['config'] as Map? ?? {}),
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum McpTransport { httpSse, stdio }

class McpServerConfig {
  final String id;
  final String name;
  final String url;
  final McpTransport transport;
  final String? authToken;
  final String? command;
  final List<String> args;
  bool connected;
  bool enabled;

  McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.transport = McpTransport.httpSse,
    this.authToken,
    this.command,
    this.args = const [],
    this.connected = false,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'transport': transport.name,
        'authToken': authToken,
        'command': command,
        'args': args,
        'enabled': enabled,
      };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        transport: McpTransport.values.firstWhere(
          (t) => t.name == json['transport'],
          orElse: () => McpTransport.httpSse,
        ),
        authToken: json['authToken'] as String?,
        command: json['command'] as String?,
        args: (json['args'] as List<dynamic>?)?.cast<String>() ?? [],
        enabled: json['enabled'] as bool? ?? true,
      );
}

class McpToolInfo {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final String serverId;

  const McpToolInfo({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.serverId,
  });
}

class McpClient {
  final McpServerConfig config;
  final _httpClient = HttpClient();
  Process? _process;
  int _requestId = 0;
  final _pendingRequests = <int, Completer<dynamic>>{};
  StreamSubscription<String>? _stdoutSub;

  McpClient(this.config);

  Future<bool> connect() async {
    try {
      if (config.transport == McpTransport.stdio) {
        return await _connectStdio();
      } else {
        return await _connectHttpSse();
      }
    } catch (e) {
      config.connected = false;
      return false;
    }
  }

  Future<bool> _connectStdio() async {
    if (config.command == null) return false;

    _process = await Process.start(
      config.command!,
      config.args,
      environment: {
        if (config.authToken != null) 'MCP_AUTH_TOKEN': config.authToken!,
      },
    );

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleMessage);

    _process!.stderr.listen((data) {
      // Log stderr for debugging
    });

    // Send initialize request
    final result = await _sendRequest('initialize', <String, dynamic>{
      'protocolVersion': '2024-11-05',
      'capabilities': <String, dynamic>{},
      'clientInfo': <String, dynamic>{
        'name': 'nova-assistant',
        'version': '1.0.0',
      },
    });

    if (result != null) {
      // Send initialized notification
      _sendNotification('notifications/initialized', {});
      config.connected = true;
      return true;
    }

    return false;
  }

  Future<bool> _connectHttpSse() async {
    final uri = Uri.parse(config.url);
    final request = await _httpClient.getUrl(uri);
    if (config.authToken != null) {
      request.headers.set('Authorization', 'Bearer ${config.authToken}');
    }
    request.headers.set('Accept', 'text/event-stream');
    final response = await request.close();

    if (response.statusCode == 200) {
      config.connected = true;

      // Start listening for SSE events
      response.transform(utf8.decoder).transform(const LineSplitter()).listen(
        _handleSseLine,
        onDone: () {
          config.connected = false;
        },
      );

      // Send initialize request via HTTP POST
      final result = await _sendHttpRequest('initialize', <String, dynamic>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{
          'name': 'nova-assistant',
          'version': '1.0.0',
        },
      });

      return result != null;
    }

    return false;
  }

  void _handleSseLine(String line) {
    if (line.startsWith('data: ')) {
      final data = line.substring(6);
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        _handleMessage(json);
      } catch (e) {
        debugPrint('McpClient._handleSseLine error parsing SSE data: $e');
      }
    }
  }

  void _handleMessage(dynamic message) {
    if (message is! Map<String, dynamic>) return;

    // Handle responses to our requests
    if (message.containsKey('id') && message.containsKey('result')) {
      final id = message['id'] as int;
      final completer = _pendingRequests.remove(id);
      completer?.complete(message['result']);
    } else if (message.containsKey('id') && message.containsKey('error')) {
      final id = message['id'] as int;
      final completer = _pendingRequests.remove(id);
      completer?.completeError(
        Exception(message['error']['message'] ?? 'MCP error'),
      );
    }
  }

  Future<List<McpToolInfo>> listTools() async {
    if (!config.connected) return [];

    final result = await _sendRequest('tools/list', {});
    if (result == null) return [];

    final tools = result['tools'] as List<dynamic>? ?? [];
    return tools.map((t) {
      final tool = t as Map<String, dynamic>;
      return McpToolInfo(
        name: tool['name'] as String,
        description: tool['description'] as String? ?? '',
        inputSchema: tool['inputSchema'] as Map<String, dynamic>? ?? {},
        serverId: config.id,
      );
    }).toList();
  }

  Future<Map<String, dynamic>?> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    if (!config.connected) return null;

    final result = await _sendRequest('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });

    if (result is Map<String, dynamic>) return result;
    return null;
  }

  Future<dynamic> _sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = ++_requestId;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    if (config.transport == McpTransport.stdio) {
      return _sendStdioRequest(id, request);
    } else {
      return _sendHttpRequest(method, params);
    }
  }

  Future<dynamic> _sendStdioRequest(
    int id,
    Map<String, dynamic> request,
  ) async {
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    _process?.stdin.writeln(jsonEncode(request));

    // Timeout after 30 seconds
    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        _pendingRequests.remove(id);
        completer.completeError(TimeoutException('MCP request timed out'));
      }
    });

    return completer.future;
  }

  Future<dynamic> _sendHttpRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    final uri = Uri.parse('${config.url}/jsonrpc');
    final request = await _httpClient.postUrl(uri);
    if (config.authToken != null) {
      request.headers.set('Authorization', 'Bearer ${config.authToken}');
    }
    request.headers.set('Content-Type', 'application/json');

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': ++_requestId,
      'method': method,
      'params': params,
    });

    request.write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      return json['result'];
    }

    return null;
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    final notification = {
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };

    if (config.transport == McpTransport.stdio) {
      _process?.stdin.writeln(jsonEncode(notification));
    }
  }

  Future<void> disconnect() async {
    config.connected = false;
    await _stdoutSub?.cancel();
    _process?.kill();
    _process = null;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Client disconnected'));
      }
    }
    _pendingRequests.clear();
  }
}

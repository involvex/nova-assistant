import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nova_assistant/services/mcp_oauth.dart';
import 'package:nova_assistant/utils/agent_debug_log.dart';

enum McpTransport { httpSse, streamableHttp, stdio }

/// How Nova authenticates to an MCP server.
enum McpAuthMode { none, bearer, apiKey, oauth }

class McpServerConfig {
  final String id;
  final String name;
  final String url;
  final McpTransport transport;
  final McpAuthMode authMode;
  final String? authToken;

  /// Named header for [McpAuthMode.apiKey] (e.g. `DD-API-KEY`).
  final String? apiKeyHeader;

  /// Extra headers (e.g. Datadog application key).
  final Map<String, String> extraHeaders;
  final String? command;
  final List<String> args;
  final String? oauthAuthUrl;
  final String? oauthTokenUrl;
  final String? oauthClientId;
  final String? oauthRedirectUri;
  final String? oauthScope;

  /// Catalog preset id when installed from the preset catalog.
  final String? presetId;
  bool connected;
  bool enabled;

  McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.transport = McpTransport.httpSse,
    this.authMode = McpAuthMode.none,
    this.authToken,
    this.apiKeyHeader,
    this.extraHeaders = const {},
    this.command,
    this.args = const [],
    this.oauthAuthUrl,
    this.oauthTokenUrl,
    this.oauthClientId,
    this.oauthRedirectUri,
    this.oauthScope,
    this.presetId,
    this.connected = false,
    this.enabled = true,
  });

  bool get hasOAuth =>
      authMode == McpAuthMode.oauth ||
      (oauthAuthUrl != null &&
          oauthAuthUrl!.isNotEmpty &&
          oauthTokenUrl != null &&
          oauthTokenUrl!.isNotEmpty &&
          oauthClientId != null &&
          oauthClientId!.isNotEmpty);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'transport': transport.name,
    'authMode': authMode.name,
    'authToken': authToken,
    'apiKeyHeader': apiKeyHeader,
    'extraHeaders': extraHeaders,
    'command': command,
    'args': args,
    'oauthAuthUrl': oauthAuthUrl,
    'oauthTokenUrl': oauthTokenUrl,
    'oauthClientId': oauthClientId,
    'oauthRedirectUri': oauthRedirectUri,
    'oauthScope': oauthScope,
    'presetId': presetId,
    'enabled': enabled,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    final modeRaw = json['authMode'] as String?;
    var authMode = McpAuthMode.none;
    if (modeRaw != null) {
      authMode = McpAuthMode.values.firstWhere(
        (m) => m.name == modeRaw,
        orElse: () => McpAuthMode.none,
      );
    } else if ((json['authToken'] as String?)?.isNotEmpty == true) {
      authMode = McpAuthMode.bearer;
    } else if ((json['oauthAuthUrl'] as String?)?.isNotEmpty == true) {
      authMode = McpAuthMode.oauth;
    }

    final extraRaw = json['extraHeaders'];
    final extraHeaders = extraRaw is Map
        ? extraRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};

    return McpServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      transport: McpTransport.values.firstWhere(
        (t) => t.name == json['transport'],
        orElse: () => McpTransport.httpSse,
      ),
      authMode: authMode,
      authToken: json['authToken'] as String?,
      apiKeyHeader: json['apiKeyHeader'] as String?,
      extraHeaders: extraHeaders,
      command: json['command'] as String?,
      args: (json['args'] as List<dynamic>?)?.cast<String>() ?? [],
      oauthAuthUrl: json['oauthAuthUrl'] as String?,
      oauthTokenUrl: json['oauthTokenUrl'] as String?,
      oauthClientId: json['oauthClientId'] as String?,
      oauthRedirectUri: json['oauthRedirectUri'] as String?,
      oauthScope: json['oauthScope'] as String?,
      presetId: json['presetId'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  McpServerConfig copyWith({
    String? name,
    String? url,
    McpTransport? transport,
    McpAuthMode? authMode,
    String? authToken,
    String? apiKeyHeader,
    Map<String, String>? extraHeaders,
    String? command,
    List<String>? args,
    String? oauthAuthUrl,
    String? oauthTokenUrl,
    String? oauthClientId,
    String? oauthRedirectUri,
    String? oauthScope,
    String? presetId,
    bool? connected,
    bool? enabled,
  }) {
    return McpServerConfig(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      transport: transport ?? this.transport,
      authMode: authMode ?? this.authMode,
      authToken: authToken ?? this.authToken,
      apiKeyHeader: apiKeyHeader ?? this.apiKeyHeader,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      command: command ?? this.command,
      args: args ?? this.args,
      oauthAuthUrl: oauthAuthUrl ?? this.oauthAuthUrl,
      oauthTokenUrl: oauthTokenUrl ?? this.oauthTokenUrl,
      oauthClientId: oauthClientId ?? this.oauthClientId,
      oauthRedirectUri: oauthRedirectUri ?? this.oauthRedirectUri,
      oauthScope: oauthScope ?? this.oauthScope,
      presetId: presetId ?? this.presetId,
      connected: connected ?? this.connected,
      enabled: enabled ?? this.enabled,
    );
  }
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
  String? lastError;
  String? _sessionId;
  String? _resolvedToken;

  McpClient(this.config);

  Future<bool> connect() async {
    lastError = null;
    try {
      await AgentDebugLog.log(
        hypothesisId: 'H5',
        location: 'mcp_client.dart:connect:start',
        message: 'MCP connect attempt',
        data: {
          'name': config.name,
          'url': config.url,
          'transport': config.transport.name,
          'hasCommand': config.command != null,
          'command': config.command,
          'hasAuth': config.authToken != null && config.authToken!.isNotEmpty,
          'hasOAuth': config.hasOAuth,
        },
      );

      _resolvedToken = await _resolveAuthToken();

      switch (config.transport) {
        case McpTransport.stdio:
          return await _connectStdio();
        case McpTransport.streamableHttp:
          return await _connectStreamableHttp();
        case McpTransport.httpSse:
          return await _connectHttpSse();
      }
    } catch (e) {
      config.connected = false;
      lastError = e.toString();
      await AgentDebugLog.log(
        hypothesisId: 'H5',
        location: 'mcp_client.dart:connect:error',
        message: 'MCP connect threw',
        data: {'name': config.name, 'error': e.toString()},
      );

      return false;
    }
  }

  Future<String?> _resolveAuthToken() async {
    if (config.authToken != null && config.authToken!.isNotEmpty) {
      return config.authToken;
    }
    if (config.authMode == McpAuthMode.oauth || config.hasOAuth) {
      return McpOAuthService.instance.loadAccessToken(config.id);
    }

    return null;
  }

  Future<bool> _connectStdio() async {
    if (config.command == null) return false;

    _process = await Process.start(
      config.command!,
      config.args,
      environment: {
        // ignore: use_null_aware_elements
        if (_resolvedToken != null) 'MCP_AUTH_TOKEN': _resolvedToken!,
      },
    );

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleMessage);

    _process!.stderr.listen((_) {});

    final result = await _sendRequest('initialize', <String, dynamic>{
      'protocolVersion': '2025-03-26',
      'capabilities': <String, dynamic>{},
      'clientInfo': <String, dynamic>{
        'name': 'nova-assistant',
        'version': '0.3.0',
      },
    });

    if (result != null) {
      _sendNotification('notifications/initialized', {});
      config.connected = true;

      return true;
    }

    return false;
  }

  Future<bool> _connectHttpSse() async {
    final uri = Uri.parse(config.url);
    final request = await _httpClient.getUrl(uri);
    _applyAuth(request);
    request.headers.set('Accept', 'text/event-stream');
    final response = await request.close();

    await AgentDebugLog.log(
      hypothesisId: 'H5',
      location: 'mcp_client.dart:_connectHttpSse:response',
      message: 'MCP HTTP/SSE response',
      data: {
        'url': config.url,
        'statusCode': response.statusCode,
        'contentType': response.headers.contentType?.toString(),
      },
    );

    if (response.statusCode == 405 || response.statusCode == 404) {
      lastError =
          'This MCP server does not support legacy HTTP/SSE (got HTTP '
          '${response.statusCode}). Try transport "Streamable HTTP" instead '
          '(Have I Been Pwned and similar hosts).';
      config.connected = false;

      return false;
    }

    if (response.statusCode == 200) {
      config.connected = true;
      response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleSseLine,
            onDone: () {
              config.connected = false;
            },
          );

      final result = await _sendHttpSseJsonRpc('initialize', <String, dynamic>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, dynamic>{
          'name': 'nova-assistant',
          'version': '0.3.0',
        },
      });

      return result != null;
    }

    lastError = 'HTTP/SSE connect failed with status ${response.statusCode}';

    return false;
  }

  /// MCP Streamable HTTP transport (spec 2025-03-26).
  ///
  /// POST JSON-RPC to the MCP endpoint with Accept for JSON and SSE.
  /// Persist `Mcp-Session-Id` from responses for subsequent calls.
  Future<bool> _connectStreamableHttp() async {
    final result = await _sendStreamableRequest('initialize', <String, dynamic>{
      'protocolVersion': '2025-03-26',
      'capabilities': <String, dynamic>{},
      'clientInfo': <String, dynamic>{
        'name': 'nova-assistant',
        'version': '0.3.0',
      },
    });

    if (result == null) {
      lastError ??= 'Streamable HTTP initialize failed';
      config.connected = false;

      return false;
    }

    await _sendStreamableNotification('notifications/initialized', {});
    config.connected = true;

    return true;
  }

  void _applyAuth(HttpClientRequest request) {
    for (final entry in config.extraHeaders.entries) {
      if (entry.key.isNotEmpty && entry.value.isNotEmpty) {
        request.headers.set(entry.key, entry.value);
      }
    }

    switch (config.authMode) {
      case McpAuthMode.none:
        break;
      case McpAuthMode.bearer:
      case McpAuthMode.oauth:
        if (_resolvedToken != null && _resolvedToken!.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $_resolvedToken');
        }
        break;
      case McpAuthMode.apiKey:
        final header =
            (config.apiKeyHeader != null &&
                config.apiKeyHeader!.trim().isNotEmpty)
            ? config.apiKeyHeader!.trim()
            : 'Authorization';
        if (_resolvedToken != null && _resolvedToken!.isNotEmpty) {
          if (header.toLowerCase() == 'authorization' &&
              !_resolvedToken!.toLowerCase().startsWith('bearer ')) {
            request.headers.set(header, 'Bearer $_resolvedToken');
          } else {
            request.headers.set(header, _resolvedToken!);
          }
        }
        break;
    }
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

    if (message.containsKey('id') && message.containsKey('result')) {
      final rawId = message['id'];
      final id = rawId is int ? rawId : int.tryParse('$rawId');
      if (id != null) {
        final completer = _pendingRequests.remove(id);
        completer?.complete(message['result']);
      }
    } else if (message.containsKey('id') && message.containsKey('error')) {
      final rawId = message['id'];
      final id = rawId is int ? rawId : int.tryParse('$rawId');
      if (id != null) {
        final completer = _pendingRequests.remove(id);
        final err = message['error'];
        final msg = err is Map ? (err['message'] ?? 'MCP error') : 'MCP error';
        completer?.completeError(Exception(msg));
      }
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

    switch (config.transport) {
      case McpTransport.stdio:
        return _sendStdioRequest(id, request);
      case McpTransport.streamableHttp:
        return _sendStreamableRequest(method, params, id: id);
      case McpTransport.httpSse:
        return _sendHttpSseJsonRpc(method, params);
    }
  }

  Future<dynamic> _sendStdioRequest(
    int id,
    Map<String, dynamic> request,
  ) async {
    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    _process?.stdin.writeln(jsonEncode(request));

    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        _pendingRequests.remove(id);
        completer.completeError(TimeoutException('MCP request timed out'));
      }
    });

    return completer.future;
  }

  Future<dynamic> _sendHttpSseJsonRpc(
    String method,
    Map<String, dynamic> params,
  ) async {
    final uri = Uri.parse('${config.url}/jsonrpc');
    final request = await _httpClient.postUrl(uri);
    _applyAuth(request);
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

  Future<dynamic> _sendStreamableRequest(
    String method,
    Map<String, dynamic> params, {
    int? id,
  }) async {
    final requestId = id ?? ++_requestId;
    final uri = Uri.parse(config.url);
    final request = await _httpClient.postUrl(uri);
    _applyAuth(request);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json, text/event-stream');
    if (_sessionId != null) {
      request.headers.set('Mcp-Session-Id', _sessionId!);
    }

    final payload = {
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    };
    request.write(jsonEncode(payload));

    final response = await request.close();
    final sessionHeader = response.headers.value('mcp-session-id');
    if (sessionHeader != null && sessionHeader.isNotEmpty) {
      _sessionId = sessionHeader;
    }

    final contentType = response.headers.contentType?.mimeType ?? '';
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 401 || response.statusCode == 403) {
      lastError =
          'Unauthorized (${response.statusCode}). Configure a Bearer token '
          'or complete OAuth for this MCP server.';

      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      lastError =
          'Streamable HTTP $method failed: HTTP ${response.statusCode} '
          '${responseBody.length > 200 ? responseBody.substring(0, 200) : responseBody}';

      return null;
    }

    if (contentType.contains('text/event-stream')) {
      return _parseSseJsonRpcResult(responseBody, requestId);
    }

    if (responseBody.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        final err = json['error'];
        lastError = err is Map
            ? (err['message']?.toString() ?? 'MCP error')
            : 'MCP error';

        return null;
      }

      return json['result'];
    } catch (e) {
      lastError = 'Failed to parse Streamable HTTP response: $e';

      return null;
    }
  }

  dynamic _parseSseJsonRpcResult(String body, int requestId) {
    for (final line in body.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final id = json['id'];
        final matches =
            id == requestId || id?.toString() == requestId.toString();
        if (matches && json.containsKey('result')) {
          return json['result'];
        }
        if (matches && json.containsKey('error')) {
          final err = json['error'];
          lastError = err is Map
              ? (err['message']?.toString() ?? 'MCP error')
              : 'MCP error';

          return null;
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> _sendStreamableNotification(
    String method,
    Map<String, dynamic> params,
  ) async {
    final uri = Uri.parse(config.url);
    final request = await _httpClient.postUrl(uri);
    _applyAuth(request);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json, text/event-stream');
    if (_sessionId != null) {
      request.headers.set('Mcp-Session-Id', _sessionId!);
    }
    request.write(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
    await request.close();
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    final notification = {'jsonrpc': '2.0', 'method': method, 'params': params};

    if (config.transport == McpTransport.stdio) {
      _process?.stdin.writeln(jsonEncode(notification));
    }
  }

  Future<void> disconnect() async {
    config.connected = false;
    _sessionId = null;
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

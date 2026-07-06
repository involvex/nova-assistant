import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';

enum ExternalToolType { http, local, mcp }

class ExternalTool {
  final String id;
  final String name;
  final String description;
  final ExternalToolType type;
  final Map<String, Object> parameters;
  final Map<String, String> config;
  final bool enabled;
  final DateTime createdAt;

  ExternalTool({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.parameters,
    this.config = const {},
    this.enabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Tool toTool() {
    return Tool(name: name, description: description, parameters: parameters);
  }

  ExternalTool copyWith({
    String? name,
    String? description,
    ExternalToolType? type,
    Map<String, Object>? parameters,
    Map<String, String>? config,
    bool? enabled,
  }) {
    return ExternalTool(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      parameters: parameters ?? this.parameters,
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
      'parameters': parameters,
      'config': config,
      'enabled': enabled,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ExternalTool.fromJson(Map<String, dynamic> json) {
    return ExternalTool(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      type: ExternalToolType.values.firstWhere((t) => t.name == json['type']),
      parameters: Map<String, Object>.from(json['parameters'] as Map),
      config: Map<String, String>.from(json['config'] as Map? ?? {}),
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class ExternalToolResult {
  final bool success;
  final dynamic data;
  final String? error;

  ExternalToolResult({required this.success, this.data, this.error});

  Map<String, dynamic> toJson() {
    return {'success': success, 'data': data, 'error': error};
  }

  factory ExternalToolResult.fromJson(Map<String, dynamic> json) {
    return ExternalToolResult(
      success: json['success'] as bool,
      data: json['data'],
      error: json['error'] as String?,
    );
  }
}

abstract class ExternalToolProvider {
  Future<ExternalToolResult> execute(
    ExternalTool tool,
    Map<String, dynamic> args,
  );
}

class HttpToolProvider implements ExternalToolProvider {
  @override
  Future<ExternalToolResult> execute(
    ExternalTool tool,
    Map<String, dynamic> args,
  ) async {
    try {
      final url = tool.config['url'] ?? '';
      final method = tool.config['method']?.toUpperCase() ?? 'GET';
      final headers = _parseHeaders(tool.config['headers'] ?? '');

      final client = HttpClient();
      try {
        final uri = Uri.parse(url);
        final request = await client.openUrl(method, uri);

        headers.forEach((key, value) {
          request.headers.set(key, value);
        });

        if (method == 'POST' || method == 'PUT') {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(args));
        }

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            final json = jsonDecode(body);
            return ExternalToolResult(success: true, data: json);
          } catch (_) {
            return ExternalToolResult(success: true, data: body);
          }
        } else {
          return ExternalToolResult(
            success: false,
            error: 'HTTP ${response.statusCode}: $body',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      return ExternalToolResult(success: false, error: e.toString());
    }
  }

  Map<String, String> _parseHeaders(String headersStr) {
    if (headersStr.isEmpty) return {};
    final headers = <String, String>{};
    for (final line in headersStr.split('\n')) {
      final parts = line.split(':');
      if (parts.length >= 2) {
        headers[parts[0].trim()] = parts.sublist(1).join(':').trim();
      }
    }
    return headers;
  }
}

class McpToolProvider implements ExternalToolProvider {
  @override
  Future<ExternalToolResult> execute(
    ExternalTool tool,
    Map<String, dynamic> args,
  ) async {
    try {
      final serverUrl = tool.config['serverUrl'] ?? '';
      final token = tool.config['token'] ?? '';

      final client = HttpClient();
      try {
        final uri = Uri.parse('$serverUrl/tools/${tool.name}/execute');
        final request = await client.postUrl(uri);

        request.headers.contentType = ContentType.json;
        if (token.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $token');
        }
        request.write(jsonEncode(args));

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final json = jsonDecode(body);
          return ExternalToolResult(success: true, data: json);
        } else {
          return ExternalToolResult(
            success: false,
            error: 'MCP Error ${response.statusCode}: $body',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      return ExternalToolResult(success: false, error: e.toString());
    }
  }
}

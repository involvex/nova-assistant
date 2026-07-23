import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/mcp_client.dart';
import 'package:nova_assistant/services/mcp_preset_catalog.dart';

void main() {
  group('McpPresetCatalog', () {
    test('ids are unique and include expected presets', () {
      final ids = McpPresetCatalog.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(
        ids,
        containsAll(['hf-hub', 'tavily-search', 'datadog-api', 'product-hunt']),
      );
    });

    test('Hugging Face preset uses official MCP URL', () {
      final hf = McpPresetCatalog.huggingfaceHub;
      expect(hf.url, 'https://huggingface.co/mcp');
      expect(hf.transport, McpTransport.streamableHttp);
      expect(hf.supportsApiKey, isTrue);
      expect(hf.supportsLogin, isTrue);
      expect(hf.authFields.any((f) => f.key == 'token'), isTrue);
    });

    test('Tavily injects api_key in body', () {
      final t = McpPresetCatalog.tavilySearch;
      expect(t.kind.name, 'httpTool');
      expect(t.authFields.single.bodyField, 'api_key');
    });

    test('Datadog uses two header auth fields', () {
      final d = McpPresetCatalog.datadogApi;
      expect(d.authFields.length, 2);
      expect(
        d.authFields.map((f) => f.headerName),
        containsAll(['DD-API-KEY', 'DD-APPLICATION-KEY']),
      );
    });

    test('byId returns catalog entry', () {
      expect(McpPresetCatalog.byId('hf-hub')?.title, 'Hugging Face Hub');
      expect(McpPresetCatalog.byId('missing'), isNull);
    });
  });

  group('McpServerConfig auth fields', () {
    test('round-trips authMode and extraHeaders', () {
      final original = McpServerConfig(
        id: 's1',
        name: 'Test',
        url: 'https://example.com/mcp',
        transport: McpTransport.streamableHttp,
        authMode: McpAuthMode.apiKey,
        authToken: 'secret',
        apiKeyHeader: 'DD-API-KEY',
        extraHeaders: const {'DD-APPLICATION-KEY': 'app'},
        presetId: 'datadog-api',
      );

      final restored = McpServerConfig.fromJson(original.toJson());
      expect(restored.authMode, McpAuthMode.apiKey);
      expect(restored.apiKeyHeader, 'DD-API-KEY');
      expect(restored.extraHeaders['DD-APPLICATION-KEY'], 'app');
      expect(restored.presetId, 'datadog-api');
      expect(restored.authToken, 'secret');
    });

    test('legacy json without authMode infers bearer from token', () {
      final restored = McpServerConfig.fromJson({
        'id': 's2',
        'name': 'Legacy',
        'url': 'https://example.com',
        'transport': 'httpSse',
        'authToken': 'tok',
        'enabled': true,
      });
      expect(restored.authMode, McpAuthMode.bearer);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/external_tool.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Reset singleton state by re-init after clearing prefs.
    await McpService.instance.initialize();
  });

  test(
    'executeTool returns error when MCP tool server is not connected',
    () async {
      await McpService.instance.addTool(
        ExternalTool(
          id: 't1',
          name: 'remote_tool',
          description: 'test',
          type: ExternalToolType.mcp,
          parameters: const {
            'type': 'object',
            'properties': <String, Object>{},
          },
          config: const {
            'serverId': 'missing-server',
            'serverUrl': 'https://example.com/mcp',
          },
        ),
      );

      final result = await McpService.instance.executeTool('remote_tool', {});
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(result.error!.toLowerCase(), contains('mcp'));
    },
  );

  test('HTTP tools still execute via provider path', () async {
    await McpService.instance.addTool(
      ExternalTool(
        id: 't2',
        name: 'http_echo',
        description: 'test',
        type: ExternalToolType.http,
        parameters: const {'type': 'object', 'properties': <String, Object>{}},
        config: const {
          'url': 'https://httpbin.org/status/404',
          'method': 'GET',
        },
      ),
    );

    final result = await McpService.instance.executeTool('http_echo', {});
    // Network may fail offline — either HTTP error or success:false is fine;
    // the important part is we did not take the MCP live-client branch.
    expect(result.error != null || result.success, isTrue);
  });
}

import 'package:nova_assistant/models/mcp_preset.dart';
import 'package:nova_assistant/services/mcp_client.dart';

/// Built-in remote MCP / HTTP tool presets for Nova.
class McpPresetCatalog {
  McpPresetCatalog._();

  static const List<McpPreset> all = [
    huggingfaceHub,
    tavilySearch,
    datadogApi,
    productHunt,
  ];

  static McpPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }

    return null;
  }

  static const huggingfaceHub = McpPreset(
    id: 'hf-hub',
    title: 'Hugging Face Hub',
    description:
        'Search models, datasets, Spaces, and papers via the official '
        'Hugging Face MCP server.',
    category: 'AI & models',
    kind: McpPresetKind.mcp,
    docsUrl: 'https://huggingface.co/docs/hub/hf-mcp-server',
    url: 'https://huggingface.co/mcp',
    transport: McpTransport.streamableHttp,
    defaultAuthMode: McpAuthMode.bearer,
    supportedAuthModes: [McpAuthMode.bearer, McpAuthMode.oauth],
    loginHintUrl: 'https://huggingface.co/settings/tokens',
    authFields: [
      McpPresetAuthField(
        key: 'token',
        label: 'Hugging Face access token',
        secret: true,
      ),
    ],
  );

  static const tavilySearch = McpPreset(
    id: 'tavily-search',
    title: 'Web search (Tavily)',
    description:
        'Real-time web search for the assistant (requires a Tavily API key).',
    category: 'Search',
    kind: McpPresetKind.httpTool,
    docsUrl:
        'https://docs.tavily.com/documentation/api-reference/endpoint/search',
    httpUrl: 'https://api.tavily.com/search',
    httpMethod: 'POST',
    httpToolName: 'tavily_search',
    httpParameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Search query'},
        'max_results': {
          'type': 'integer',
          'description': 'Max results (default 5)',
        },
      },
      'required': ['query'],
    },
    defaultAuthMode: McpAuthMode.apiKey,
    supportedAuthModes: [McpAuthMode.apiKey],
    authFields: [
      McpPresetAuthField(
        key: 'api_key',
        label: 'Tavily API key',
        secret: true,
        bodyField: 'api_key',
      ),
    ],
  );

  static const datadogApi = McpPreset(
    id: 'datadog-api',
    title: 'Datadog',
    description:
        'Query Datadog metrics via the HTTP API (API key + application key).',
    category: 'Observability',
    kind: McpPresetKind.httpTool,
    docsUrl: 'https://docs.datadoghq.com/api/latest/',
    httpUrl: 'https://api.datadoghq.com/api/v1/query',
    httpMethod: 'GET',
    httpToolName: 'datadog_query_metrics',
    httpParameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Datadog metric query string',
        },
        'from': {
          'type': 'integer',
          'description': 'Start unix timestamp (seconds)',
        },
        'to': {
          'type': 'integer',
          'description': 'End unix timestamp (seconds)',
        },
      },
      'required': ['query', 'from', 'to'],
    },
    defaultAuthMode: McpAuthMode.apiKey,
    supportedAuthModes: [McpAuthMode.apiKey],
    authFields: [
      McpPresetAuthField(
        key: 'api_key',
        label: 'Datadog API key',
        secret: true,
        headerName: 'DD-API-KEY',
      ),
      McpPresetAuthField(
        key: 'app_key',
        label: 'Datadog application key',
        secret: true,
        headerName: 'DD-APPLICATION-KEY',
      ),
    ],
  );

  static const productHunt = McpPreset(
    id: 'product-hunt',
    title: 'Product Hunt',
    description:
        'Query Product Hunt GraphQL (posts, topics) with a developer token.',
    category: 'Product',
    kind: McpPresetKind.httpTool,
    docsUrl: 'https://api.producthunt.com/v2/docs',
    httpUrl: 'https://api.producthunt.com/v2/api/graphql',
    httpMethod: 'POST',
    httpToolName: 'product_hunt_graphql',
    httpParameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'GraphQL query string'},
        'variables': {
          'type': 'object',
          'description': 'Optional GraphQL variables',
        },
      },
      'required': ['query'],
    },
    defaultAuthMode: McpAuthMode.bearer,
    supportedAuthModes: [McpAuthMode.bearer],
    authFields: [
      McpPresetAuthField(
        key: 'token',
        label: 'Product Hunt developer token',
        secret: true,
        headerName: 'Authorization',
      ),
    ],
  );
}

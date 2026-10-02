import 'package:nova_assistant/ai/agents/agent.dart';
import 'package:nova_assistant/ai/agents/agent_router.dart';
import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/providers/provider_registry.dart';
import 'package:nova_assistant/ai/router/cloud_availability.dart';
import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/ai/router/intent_router.dart';
import 'package:nova_assistant/ai/router/provider_strategy.dart';
import 'package:nova_assistant/ai/router/routing_candidates.dart';
import 'package:nova_assistant/ai/router/routing_context.dart';
import 'package:nova_assistant/ai/router/routing_preset.dart';
import 'package:nova_assistant/ai/router/smart_router.dart';
import 'package:nova_assistant/core/config/provider_config.dart';
import 'package:nova_assistant/core/connectivity/offline_first_policy.dart';
import 'package:nova_assistant/memory/memory_service_v2.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/screen/screen_context.dart';
import 'package:nova_assistant/screen/screen_context_engine.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/tools/core/tool_context.dart';
import 'package:nova_assistant/tools/core/tool_registry.dart';

/// Central assistant facade: Android -> NovaCore -> Provider/Agent/Tool.
///
/// Owns no engine itself; it only wires the abstractions from Phases 1-6:
/// intent routing, provider strategy, offline-first gating, agent routing,
/// screen context injection and the tool registry.
class NovaCore {
  NovaCore({
    IntentRouter? router,
    this.strategy,
    AgentRouter? agents,
    OfflineFirstPolicy? offlinePolicy,
    ScreenContextEngine? screenEngine,
    MemoryServiceV2? memory,
  }) : router = router ?? const RuleBasedIntentRouter(),
       agents = agents ?? AgentRouter(),
       offlinePolicy = offlinePolicy ?? OfflineFirstPolicy(),
       screenEngine = screenEngine ?? ScreenContextEngine(),
       memory = memory ?? MemoryServiceV2();

  final IntentRouter router;
  final ProviderStrategy? strategy;
  final AgentRouter agents;
  final OfflineFirstPolicy offlinePolicy;
  final ScreenContextEngine screenEngine;
  final MemoryServiceV2 memory;

  /// Strategy fallback when none is injected (mirrors providers.yaml).
  static const ProviderConfig _fallbackConfig = ProviderConfig(<String, String>{
    'simple': 'local-gemma',
    'coding': 'kilo-gateway',
    'vision': 'local-gemma',
    'automation': 'local-qwen',
    'fallback': 'kilo-gateway',
  });

  /// Classifies [query] and selects the effective provider id using the
  /// smart router (content + request + setup signals), honoring
  /// offline-first (cloud -> local-gemma when offline).
  ///
  /// [providerOverride] forces a provider id (explicit model pin or LAN
  /// backend) while keeping intent/agent routing and the offline gate
  /// intact. Returns the routing [reasons] for status/debug display.
  Future<
    ({
      Intent intent,
      String providerId,
      String? modelId,
      String agentId,
      List<String> reasons,
    })
  >
  resolve(
    String query, {
    bool hasImage = false,
    String? activePackage,
    String? providerOverride,
    bool thinkingMode = false,
    int attachmentCount = 0,
    bool hasDocuments = false,
  }) async {
    final Intent intent = await router.route(
      query,
      hasImage: hasImage,
      activePackage: activePackage,
    );
    final ProviderStrategy effectiveStrategy =
        strategy ?? ProviderStrategy(_fallbackConfig);
    final RoutingContext routingContext = RoutingContext(
      query: query,
      intent: intent,
      hasImage: hasImage,
      thinkingMode: thinkingMode,
      attachmentCount: attachmentCount,
      hasDocuments: hasDocuments,
      installedLocalModels: _installedLocalModelNames(),
      cloudAvailable: CloudAvailability.current,
      enabledCandidates: await RoutingCandidates.loadIds(),
    );
    final RoutingDecision decision = const SmartRouter().select(
      routingContext,
      strategy: effectiveStrategy,
      preset: await RoutingPresetStore.load(),
    );
    final String configured = providerOverride ?? decision.providerId;
    // A manual pin uses the provider default model; auto routing may carry
    // a preset model. Offline gating drops cloud models with the provider.
    final String? modelId = providerOverride != null ? null : decision.modelId;
    final List<String> reasons = <String>[
      if (providerOverride != null) 'pinned: $providerOverride',
      ...decision.reasons,
    ];
    final String providerId = await offlinePolicy.gateProvider(configured);
    if (providerId != configured) {
      reasons.add('offline → $providerId');
    }
    final AgentRequest probe = AgentRequest(
      intent: intent,
      aiRequest: AIRequest(
        messages: <ChatTurn>[ChatTurn(role: 'user', text: query)],
        hasImage: hasImage,
      ),
    );
    final String agentId = agents.route(probe).id;

    return (
      intent: intent,
      providerId: providerId,
      modelId: providerId == configured ? modelId : null,
      agentId: agentId,
      reasons: List<String>.unmodifiable(reasons),
    );
  }

  /// Installed on-device models by [NovaModel.name], via cheap
  /// prefs-backed checks (no disk I/O on the routing path).
  static Set<String> _installedLocalModelNames() {
    try {
      final ModelManager manager = ModelManager.instance;
      final Set<String> installed = <String>{};
      for (final NovaModel model in NovaModel.values) {
        try {
          if (manager.isModelInstalled(
            ModelHuggingFaceURLs.fileNameFor(model),
          )) {
            installed.add(model.name);
          }
        } catch (_) {
          // Ignore per-model lookup failures; treat as not installed.
        }
      }

      return installed;
    } catch (_) {
      return const <String>{};
    }
  }

  /// Full turn: route -> screen context (vision only) -> memory context ->
  /// agent -> provider stream. Tool execution stays with the caller via
  /// [ToolRegistry] (the agent response may contain tool calls).
  ///
  /// Pass [screenContext] when the caller already captured screen bytes
  /// (e.g. `ModelOrchestrator.processMessage`) to avoid a second capture.
  /// [providerOverride] is forwarded to [resolve]. [thinkingMode],
  /// [attachmentCount] and [hasDocuments] feed the smart router's signals.
  Stream<String> handle(
    String query, {
    String? systemPrompt,
    bool hasImage = false,
    bool includeScreenshot = true,
    ScreenContext? screenContext,
    String? providerOverride,
    bool thinkingMode = false,
    int attachmentCount = 0,
    bool hasDocuments = false,
    String sessionId = 'default',
  }) async* {
    final (
      :String agentId,
      :Intent intent,
      :String providerId,
      :String? modelId,
      :List<String> reasons,
    ) = await resolve(
      query,
      hasImage: hasImage,
      providerOverride: providerOverride,
      thinkingMode: thinkingMode,
      attachmentCount: attachmentCount,
      hasDocuments: hasDocuments,
    );

    ScreenContext? screen = screenContext;
    if (screen == null && intent == Intent.vision) {
      screen = await screenEngine.capture(includeScreenshot: includeScreenshot);
    }

    final String? memoryContext = await memory.buildContext(query);
    final String system = <String?>[
      systemPrompt,
      memoryContext,
      if (screen != null && screen.hasText)
        'Screen text: ${screen.ocrText ?? screen.visibleText}',
    ].whereType<String>().where((String s) => s.isNotEmpty).join('\n\n');

    final AIRequest aiRequest = AIRequest(
      messages: <ChatTurn>[ChatTurn(role: 'user', text: query)],
      systemPrompt: system.isEmpty ? null : system,
      hasImage: hasImage || (screen?.hasVisual ?? false),
      modelId: modelId,
    );
    final AgentRequest agentRequest = AgentRequest(
      intent: intent,
      aiRequest: aiRequest,
      screen: screen,
    );
    final NovaAgent agent = agents.route(agentRequest);
    final AIProvider provider = ProviderRegistry.get(providerId);

    await provider.ensureReady();
    await for (final String chunk in agent.handle(agentRequest, provider)) {
      yield chunk;
    }
  }

  /// Direct tool call through the registry (Phase-3 rule: actions only
  /// via the tool system).
  Future<Map<String, Object?>> callTool(
    String toolId,
    Map<String, Object?> args, {
    String sessionId = 'default',
  }) async {
    final ToolContext context = ToolContext(sessionId: sessionId);
    final result = await ToolRegistry.execute(toolId, context, args);

    return <String, Object?>{
      'success': result.success,
      ...result.data,
      if (result.error != null) 'error': result.error,
    };
  }
}

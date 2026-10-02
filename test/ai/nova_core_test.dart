import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/ai/nova_core.dart';
import 'package:nova_assistant/ai/providers/ai_provider.dart';
import 'package:nova_assistant/ai/providers/provider_capabilities.dart';
import 'package:nova_assistant/ai/providers/provider_registry.dart';
import 'package:nova_assistant/ai/router/cloud_availability.dart';
import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/ai/router/provider_strategy.dart';
import 'package:nova_assistant/core/config/provider_config.dart';
import 'package:nova_assistant/core/connectivity/offline_first_policy.dart';
import 'package:nova_assistant/memory/memory_service_v2.dart';
import 'package:nova_assistant/screen/screen_context_engine.dart';
import 'package:nova_assistant/tools/core/tool_registry.dart';
import 'package:nova_assistant/tools/implementations/built_in_tools.dart';

class _FakeProvider implements AIProvider {
  _FakeProvider(this._id, {this.local = false});

  final String _id;
  final bool local;

  @override
  String get id => _id;

  @override
  Set<ProviderCapability> get capabilities => <ProviderCapability>{
    ProviderCapability.chat,
    ProviderCapability.streaming,
  };

  @override
  bool get isLocal => local;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<String> chat(AIRequest request) async => 'hello from $_id';

  @override
  Stream<String> chatStream(AIRequest request) async* {
    yield 'hello from $_id';
  }

  @override
  Future<List<double>> embed(String text) {
    throw UnsupportedError('no embeddings');
  }
}

NovaCore _buildCore({required bool online}) {
  const ProviderConfig config = ProviderConfig(<String, String>{
    'simple': 'local-gemma',
    'coding': 'openrouter',
    'vision': 'local-gemma',
    'automation': 'local-qwen',
    'fallback': 'openrouter',
  });

  return NovaCore(
    strategy: ProviderStrategy(config),
    offlinePolicy: OfflineFirstPolicy(checkOnline: () async => online),
    screenEngine: ScreenContextEngine(screenshotProvider: () async => null),
    memory: MemoryServiceV2(),
  );
}

void main() {
  setUp(() {
    ProviderRegistry.clearForTesting();
    ProviderRegistry.registerAll(<AIProvider>[
      _FakeProvider('local-gemma', local: true),
      _FakeProvider('local-qwen', local: true),
      _FakeProvider('openrouter'),
    ]);
    CloudAvailability.update(const <String, bool>{'openrouter': true});
    ToolRegistry.clearForTesting();
    ToolRegistry.registerAll(
      allNovaTools(
        handler: (String id, Map<String, Object?> args) async =>
            <String, Object?>{'success': true, 'tool': id},
      ),
    );
  });

  tearDown(() {
    ProviderRegistry.clearForTesting();
    ToolRegistry.clearForTesting();
    CloudAvailability.resetForTesting();
  });

  group('NovaCore.resolve', () {
    test('time question resolves to local-gemma + fallback agent', () async {
      final NovaCore core = _buildCore(online: true);
      final ({
        String agentId,
        Intent intent,
        String providerId,
        String? modelId,
        List<String> reasons,
      })
      plan = await core.resolve('Wie spät ist es?');

      expect(plan.intent, Intent.local);
      expect(plan.providerId, 'local-gemma');
      expect(plan.agentId, 'fallback');
    });

    test('offline gates cloud to local-gemma', () async {
      final NovaCore core = _buildCore(online: false);
      final ({
        String agentId,
        Intent intent,
        String providerId,
        String? modelId,
        List<String> reasons,
      })
      plan = await core.resolve('Analysiere diese APK im Detail bitte');

      expect(plan.intent, Intent.cloud);
      expect(plan.providerId, 'local-gemma');
    });

    test('online cloud stays on openrouter', () async {
      final NovaCore core = _buildCore(online: true);
      final ({
        String agentId,
        Intent intent,
        String providerId,
        String? modelId,
        List<String> reasons,
      })
      plan = await core.resolve('Analysiere diese APK im Detail bitte');

      expect(plan.providerId, 'openrouter');
      expect(plan.agentId, 'coding');
    });
  });

  group('NovaCore.handle', () {
    test('streams provider text end to end', () async {
      final NovaCore core = _buildCore(online: true);
      final StringBuffer buffer = StringBuffer();
      await for (final String chunk in core.handle('Hallo Nova')) {
        buffer.write(chunk);
      }

      expect(buffer.toString(), contains('local-gemma'));
    });

    test('vision turn works without screenshot provider', () async {
      final NovaCore core = _buildCore(online: true);
      final StringBuffer buffer = StringBuffer();
      await for (final String chunk in core.handle(
        'Was sehe ich auf dem Bildschirm?',
      )) {
        buffer.write(chunk);
      }

      expect(buffer.toString(), isNotEmpty);
    });
  });

  group('NovaCore providerOverride', () {
    test('override forces provider regardless of intent', () async {
      final NovaCore core = _buildCore(online: true);
      final ({
        String agentId,
        Intent intent,
        String providerId,
        String? modelId,
        List<String> reasons,
      })
      plan = await core.resolve('Hallo Nova', providerOverride: 'openrouter');

      expect(plan.intent, Intent.local);
      expect(plan.providerId, 'openrouter');
    });

    test('offline gates override back to local', () async {
      final NovaCore core = _buildCore(online: false);
      final ({
        String agentId,
        Intent intent,
        String providerId,
        String? modelId,
        List<String> reasons,
      })
      plan = await core.resolve('Hallo Nova', providerOverride: 'openrouter');

      expect(plan.providerId, 'local-gemma');
    });

    test('handle honors the override end to end', () async {
      final NovaCore core = _buildCore(online: true);
      final StringBuffer buffer = StringBuffer();
      await for (final String chunk in core.handle(
        'Hallo Nova',
        providerOverride: 'openrouter',
      )) {
        buffer.write(chunk);
      }

      expect(buffer.toString(), contains('openrouter'));
    });
  });

  group('NovaCore.callTool', () {
    test('routes through registry', () async {
      final NovaCore core = _buildCore(online: true);
      final Map<String, Object?> result = await core.callTool(
        'get_time',
        const <String, Object?>{},
      );

      expect(result['success'], isTrue);
    });
  });
}

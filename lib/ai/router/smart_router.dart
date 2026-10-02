import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/ai/router/provider_strategy.dart';
import 'package:nova_assistant/ai/router/routing_candidates.dart';
import 'package:nova_assistant/ai/router/routing_context.dart';
import 'package:nova_assistant/ai/router/routing_preset.dart';

/// Smart-routing decision with human-readable reasons (shown in debug
/// status, used by tests to pin behavior).
class RoutingDecision {
  const RoutingDecision({
    required this.intent,
    required this.providerId,
    this.modelId,
    this.reasons = const <String>[],
  });

  final Intent intent;
  final String providerId;

  /// Explicit preset model for this turn, or null for the provider default
  /// (the model configured in settings).
  final String? modelId;
  final List<String> reasons;
}

/// Content + request + setup aware provider selection.
///
/// Principles (local-first):
/// - Device actions (tool/automation) always stay on-device — only the
///   local engine can execute tools.
/// - Vision stays on-device when a vision model is installed (private,
///   fast); otherwise it uses the first configured cloud provider.
/// - Cloud intents use the first *configured* cloud provider in strategy
///   order, falling back to on-device with an explicit reason instead of
///   failing on a missing token.
/// - Plain chat stays local unless the user mapped `simple` to cloud in
///   `providers.yaml` AND that provider is configured.
/// - Heavy pasted content (>1200 chars / code fences) escalates to cloud
///   when one is configured — it usually exceeds comfortable on-device
///   context and benefits from stronger models.
class SmartRouter {
  const SmartRouter();

  static const List<String> cloudPreferenceOrder = <String>[
    'kilo-gateway',
    'openrouter',
    'groq',
    'opencode-zen',
    'openai',
  ];

  RoutingDecision select(
    RoutingContext context, {
    required ProviderStrategy strategy,
    RoutingPreset preset = RoutingPreset.free,
  }) {
    final List<String> reasons = <String>[];
    // Toggle-aware cloud map: untoggled providers behave as unconfigured.
    final Map<String, bool> clouds = <String, bool>{};
    context.cloudAvailable.forEach((String id, bool hasToken) {
      if (hasToken &&
          context.isCandidateEnabled(RoutingCandidates.cloudId(id))) {
        clouds[id] = true;
      } else if (hasToken) {
        reasons.add('$id toggled off for routing');
      }
    });

    switch (context.intent) {
      case Intent.tool:
      case Intent.automation:
        final String local = strategy.providerIdFor(context.intent);
        reasons.add('device action → on-device ($local)');

        return RoutingDecision(
          intent: context.intent,
          providerId: local.startsWith('local-') ? local : 'local-qwen',
          reasons: reasons,
        );

      case Intent.vision:
        if (context.hasEnabledLocalVision) {
          reasons.add('vision model on-device → private + fast');

          return RoutingDecision(
            intent: context.intent,
            providerId: 'local-gemma',
            reasons: reasons,
          );
        }
        final String? visionCloud = firstAvailableCloud(
          clouds,
          extraFirst: <String>[strategy.providerIdFor(context.intent)],
        );
        if (visionCloud != null) {
          reasons.add(
            context.hasLocalVision
                ? 'local vision toggled off → $visionCloud'
                : 'no local vision model → $visionCloud',
          );

          return RoutingDecision(
            intent: context.intent,
            providerId: visionCloud,
            reasons: reasons,
          );
        }
        reasons.add('no vision model anywhere → local (will prompt install)');

        return RoutingDecision(
          intent: context.intent,
          providerId: 'local-gemma',
          reasons: reasons,
        );

      case Intent.cloud:
        // The preset chain is authoritative for cloud turns (provider +
        // model verified live). Strategy coding/fallback keys are kept for
        // local mappings and backward compatibility.
        final CloudTarget? target = firstAvailableTarget(
          clouds,
          presetTargets(preset),
        );
        if (target != null) {
          reasons.add(
            'cloud intent → ${target.providerId}'
            '${target.modelId != null ? ' · ${target.modelId}' : ''}'
            ' (${preset.name})',
          );

          return RoutingDecision(
            intent: context.intent,
            providerId: target.providerId,
            modelId: target.modelId,
            reasons: reasons,
          );
        }
        reasons.add('cloud intent but no cloud token → on-device fallback');

        return RoutingDecision(
          intent: context.intent,
          providerId: 'local-gemma',
          reasons: reasons,
        );

      case Intent.local:
        if (context.isHeavyContent) {
          final CloudTarget? heavyTarget = firstAvailableTarget(
            clouds,
            presetTargets(preset),
          );
          if (heavyTarget != null) {
            reasons.add(
              'heavy content (${context.queryLength} chars) → '
              '${heavyTarget.providerId}'
              '${heavyTarget.modelId != null ? ' · ${heavyTarget.modelId}' : ''}',
            );

            return RoutingDecision(
              intent: Intent.cloud,
              providerId: heavyTarget.providerId,
              modelId: heavyTarget.modelId,
              reasons: reasons,
            );
          }
          reasons.add('heavy content but no cloud → on-device');
        }
        final String simple = strategy.providerIdFor(context.intent);
        if (!simple.startsWith('local-')) {
          final String? simpleCloud = firstAvailableCloud(
            clouds,
            extraFirst: <String>[simple],
          );
          if (simpleCloud != null) {
            reasons.add('simple mapped to $simpleCloud in config');

            return RoutingDecision(
              intent: context.intent,
              providerId: simpleCloud,
              reasons: reasons,
            );
          }
          reasons.add('simple mapped to $simple but not configured → local');
        } else {
          reasons.add('plain chat → on-device');
        }

        return RoutingDecision(
          intent: context.intent,
          providerId: 'local-gemma',
          reasons: reasons,
        );
    }
  }

  /// First provider id with a configured token, honoring [extraFirst]
  /// (strategy picks) before the built-in preference order.
  static String? firstAvailableCloud(
    Map<String, bool> cloudAvailable, {
    List<String> extraFirst = const <String>[],
  }) {
    final List<String> order = <String>[...extraFirst, ...cloudPreferenceOrder];
    final Set<String> seen = <String>{};
    for (final String id in order) {
      if (!seen.add(id)) {
        continue;
      }
      if (id.startsWith('local-')) {
        continue;
      }
      if (cloudAvailable[id] == true) {
        return id;
      }
    }

    return null;
  }

  /// First available (provider, model) target in order. Strategy picks
  /// (null model = provider default) come first; a later preset entry
  /// upgrades the model when it names the same provider explicitly.
  static CloudTarget? firstAvailableTarget(
    Map<String, bool> cloudAvailable,
    List<CloudTarget> ordered,
  ) {
    final Map<String, CloudTarget> merged = <String, CloudTarget>{};
    for (final CloudTarget target in ordered) {
      if (target.providerId.startsWith('local-')) {
        continue;
      }
      final CloudTarget? existing = merged[target.providerId];
      if (existing == null ||
          (existing.modelId == null && target.modelId != null)) {
        merged[target.providerId] = target;
      }
    }
    for (final MapEntry<String, CloudTarget> entry in merged.entries) {
      if (cloudAvailable[entry.key] == true) {
        return entry.value;
      }
    }

    return null;
  }
}

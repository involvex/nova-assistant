import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/ai/router/routing_candidates.dart';

/// Everything the smart router knows about a turn before deciding.
///
/// *Content*: the query itself (length, code fences, complexity markers).
/// *Request*: attachments, image payload, thinking mode.
/// *Setup*: device + configuration state (installed locals, cloud tokens,
/// network). All fields are precomputed by the caller so the router itself
/// stays a pure, unit-testable function.
class RoutingContext {
  const RoutingContext({
    required this.query,
    required this.intent,
    this.hasImage = false,
    this.thinkingMode = false,
    this.attachmentCount = 0,
    this.hasDocuments = false,
    this.installedLocalModels = const <String>{},
    this.cloudAvailable = const <String, bool>{},
    this.online = true,
    this.enabledCandidates,
  });

  /// Raw user query.
  final String query;

  /// Pre-classified intent (rule-based; later a small local model).
  final Intent intent;

  final bool hasImage;
  final bool thinkingMode;
  final int attachmentCount;
  final bool hasDocuments;

  /// Installed on-device models by [NovaModel.name]
  /// (`gemma4E2b`, `fastvlm`, `smollm`, …).
  final Set<String> installedLocalModels;

  /// Cloud provider id → token configured.
  final Map<String, bool> cloudAvailable;

  final bool online;

  /// Toggled routing candidates (`local:…`/`custom:…`/`cloud:…`), or null
  /// when never saved (= everything participates).
  final Set<String>? enabledCandidates;

  int get queryLength => query.length;

  bool get hasCodeFence => query.contains('```');

  /// Long, structured, multi-part content that exceeds comfortable
  /// on-device context (code dumps, pasted docs, specs).
  bool get isHeavyContent => queryLength > 1200 || hasCodeFence;

  bool get hasLocalVision =>
      installedLocalModels.contains('gemma4E2b') ||
      installedLocalModels.contains('fastvlm');

  /// Candidate toggle check (null set = everything participates).
  bool isCandidateEnabled(String candidateId) {
    return RoutingCandidates.isEnabled(enabledCandidates, candidateId);
  }

  /// Installed AND toggled-on vision models.
  bool get hasEnabledLocalVision =>
      (installedLocalModels.contains('gemma4E2b') &&
          isCandidateEnabled(RoutingCandidates.localId('gemma4E2b'))) ||
      (installedLocalModels.contains('fastvlm') &&
          isCandidateEnabled(RoutingCandidates.localId('fastvlm')));
}

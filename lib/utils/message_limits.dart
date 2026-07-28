import 'package:flutter/foundation.dart';

import 'package:nova_assistant/models/model_info.dart';

enum MessageLimitTier { fast, medium, large }

/// Model-aware character limits for chat input stability.
class MessageLimits {
  const MessageLimits._();

  static const contextBudgetRatio = 0.6;
  static const highContextBudgetRatio = 0.7;

  /// Edge Gallery / LiteRT-LM native ceiling for Gemma 4 E2B/E4B.
  static const gemma4NativeMaxContext = 32000;

  /// Cached device RAM (MB) from [MemoryDiagnosticsService].
  ///
  /// Used by [recommendedGemma4Kv] when callers do not pass [totalMemMb].
  static int? deviceTotalMemMb;

  /// Updates the process-wide RAM cache used for KV recommendations.
  static void setDeviceTotalMemMb(int? mb) {
    deviceTotalMemMb = mb;
  }

  /// Fixed token overhead baked into Gemma 4 sessions (jinja FC template, etc.).
  static const gemma4JinjaOverheadTokens = 400;

  /// Typical system prompt + role + identity overhead.
  ///
  /// Kept for backward compatibility with callers that only need a flat
  /// reservation. Use [computedOverheadFor] when the real system prompt
  /// length is known — it gives a far more accurate number.
  static const systemPromptOverheadTokens = 220;

  /// Per-tool overhead when the schema is passed to native function calling.
  /// Measured against Gemma 4 with the bundled tool set (~35–80 tokens each).
  static const toolSchemaOverheadBaseTokens = 80;
  static const toolSchemaOverheadPerToolTokens = 35;

  /// Estimated cost of the text-mode tool essay injected into the system
  /// prompt when native FC is unavailable.
  static const textToolPromptOverheadTokens = 120;

  /// RAG + attachment context overhead (mostly chat-template wrappers).
  static const ragOverheadTokens = 40;
  static const attachmentOverheadTokens = 60;

  /// Conservative vision-image token estimate (phone screenshot tiles).
  static const visionImageTokenEstimate = 1024;

  /// Leave headroom so native prefill never sits on the KV ceiling.
  ///
  /// Gemma 4's tokenizer produces ~30–60 % more tokens than chars/4, so the
  /// historical 128-token margin was too tight and produced "Input token ids
  /// are too long" errors after a handful of turns. 256 is the minimum that
  /// holds across short English chat, code, and numbers.
  static const kvSafetyMarginTokens = 256;

  /// Larger safety margin for Gemma 4 Android where the jinja FC template +
  /// 16 native tool schemas routinely consume 600–1 000 KV tokens.
  static const gemma4KvSafetyMarginTokens = 384;

  static const exhaustedBudgetFloorChars = 400;

  /// Real-token-per-character ratios for each model's tokenizer.
  ///
  /// The legacy `(text.length / 4).round()` estimator systematically
  /// underestimates Gemma 4's actual SentencePiece output by 30-60 % on
  /// English chat and up to 80 % on code / numbers / non-ASCII. Use the
  /// table below for budget-critical paths (replay budget, pre-flight
  /// validation, native FC overflow detection).
  static double realTokenRatio(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return 0.36;
      case NovaModel.fastvlm:
        return 0.33;
      case NovaModel.gemma3_1b:
        return 0.33;
      case NovaModel.gemma4E2b:
        return 0.32;
    }
  }

  /// Returns a smarter token estimate that accounts for code-like runs and
  /// digits, which the tokenizer fragments far more aggressively than prose.
  ///
  /// Single linear pass — fast enough to call inside the per-turn pre-flight
  /// without adding noticeable latency.
  static int estimateRealTokens(String text, {NovaModel? model}) {
    if (text.isEmpty) return 0;
    final ratio = realTokenRatio(model ?? NovaModel.gemma4E2b);
    final len = text.length;

    var codeChars = 0;
    var digitChars = 0;
    for (var i = 0; i < len; i++) {
      final c = text.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39;
      // Identifiers, brackets, operators, punctuation that SentencePiece
      // typically splits into single tokens.
      final isCodey =
          c == 0x5F || // _
          c == 0x7B ||
          c == 0x7D || // { }
          c == 0x28 ||
          c == 0x29 || // ( )
          c == 0x3B ||
          c == 0x3D || // ; =
          c == 0x3C ||
          c == 0x3E || // < >
          c == 0x2F ||
          c == 0x5C || // / \
          c == 0x5B ||
          c == 0x5D || // [ ]
          c == 0x2B ||
          c == 0x2D ||
          c == 0x2A ||
          c == 0x25 ||
          c == 0x24 ||
          c == 0x23 ||
          c == 0x40 ||
          c == 0x7E;
      if (isDigit) {
        digitChars++;
      } else if (isCodey) {
        codeChars++;
      }
    }
    final other = len - digitChars - codeChars;
    final tokens = (other * ratio) + (codeChars * 0.45) + (digitChars * 0.55);

    return tokens.round();
  }

  /// Returns the [kvSafetyMarginTokens] appropriate for [model].
  ///
  /// Gemma 4 has a heavier chat template + tool schema; other models stay at
  /// the lower base margin so they don't lose usable budget unnecessarily.
  static int safetyMarginFor(NovaModel model) {
    if (model == NovaModel.gemma4E2b) return gemma4KvSafetyMarginTokens;

    return kvSafetyMarginTokens;
  }

  /// Returns the realistic token overhead already consumed by the prompt
  /// scaffolding (system prompt length + native tool schemas + text tool
  /// essay + RAG/attachment wrappers) before user / history tokens are
  /// counted.
  ///
  /// Replaces the historical flat [systemPromptOverheadTokens] = 220 used in
  /// replay-budget math, which under-reserved by ~500–900 tokens on Gemma 4
  /// Android and caused "Input token ids are too long" after a handful of
  /// turns.
  static int computedOverheadFor(
    NovaModel model, {
    int systemPromptChars = 0,
    int toolsCount = 0,
    bool textToolPrompt = false,
    bool hasRag = false,
    bool hasAttachments = false,
  }) {
    var overhead = systemPromptOverheadTokens;
    if (model == NovaModel.gemma4E2b) {
      overhead += gemma4JinjaOverheadTokens;
    }
    if (systemPromptChars > 0) {
      overhead += estimateRealTokens('x' * systemPromptChars, model: model);
    }
    if (toolsCount > 0) {
      overhead +=
          toolSchemaOverheadBaseTokens +
          (toolsCount * toolSchemaOverheadPerToolTokens);
    }
    if (textToolPrompt) overhead += textToolPromptOverheadTokens;
    if (hasRag) overhead += ragOverheadTokens;
    if (hasAttachments) overhead += attachmentOverheadTokens;

    return overhead;
  }

  /// RAM-aware KV for Gemma 4 (Edge Gallery uses up to 32K on capable devices).
  ///
  /// Tiers follow Gallery-style memory gating so 12 GB phones are not stuck on
  /// the old 2048 Android default.
  static int recommendedGemma4Kv({bool highContext = false, int? totalMemMb}) {
    final mem = totalMemMb ?? deviceTotalMemMb;
    if (mem != null) {
      if (mem < 6000) return highContext ? 4096 : 2048;
      if (mem < 8000) return highContext ? 8192 : 4096;
      if (mem < 12000) return highContext ? 16384 : 8192;

      return highContext ? gemma4NativeMaxContext : 16384;
    }

    // Unknown RAM: still far above the historical 2048 Android trap.
    return highContext ? 8192 : 4096;
  }

  /// Allowed presets for custom-model import (Edge Gallery style).
  static const customContextPresets = <int>[
    1024,
    2048,
    4096,
    8192,
    16384,
    gemma4NativeMaxContext,
  ];

  /// Clamps a user-entered custom context to a safe LiteRT range.
  static int clampCustomContextTokens(int value) {
    if (value < 512) return 512;
    if (value > gemma4NativeMaxContext) return gemma4NativeMaxContext;

    return value;
  }

  static MessageLimitTier tierFor({
    NovaModel? model,
    bool isCustomModel = false,
    bool highContext = false,
  }) {
    if (isCustomModel) return MessageLimitTier.large;
    if (model == null || model == NovaModel.smollm) {
      return MessageLimitTier.fast;
    }
    if (model == NovaModel.fastvlm || model == NovaModel.gemma3_1b) {
      return MessageLimitTier.medium;
    }
    if (model == NovaModel.gemma4E2b) {
      // Large user-message caps once KV is in Edge Gallery territory.
      final kv = recommendedGemma4Kv(highContext: highContext);
      if (kv >= 8192 || highContext) return MessageLimitTier.large;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        return MessageLimitTier.medium;
      }
    }

    return MessageLimitTier.large;
  }

  /// Resolves the tier used for limits when Auto mode forces a heavy model.
  static MessageLimitTier effectiveTier({
    NovaModel? selectedModel,
    bool isAutoMode = false,
    bool isCustomModel = false,
    NovaModel? effectiveModel,
    bool highContext = false,
  }) {
    if (isCustomModel) return MessageLimitTier.large;
    final resolved = effectiveModel ?? selectedModel;
    if (resolved != null) {
      return tierFor(
        model: resolved,
        isCustomModel: false,
        highContext: highContext,
      );
    }
    if (isAutoMode) {
      return tierFor(
        model: NovaModel.gemma4E2b,
        isCustomModel: false,
        highContext: highContext,
      );
    }

    return MessageLimitTier.fast;
  }

  static int kvTokenLimitFor(
    NovaModel model, {
    bool highContext = false,
    int? totalMemMb,
  }) {
    switch (model) {
      case NovaModel.smollm:
        // Match ekv1280 asset headroom; 512 starved system+history → OUT_OF_RANGE.
        return 1024;
      case NovaModel.fastvlm:
        return 1024;
      case NovaModel.gemma3_1b:
        return 2048;
      case NovaModel.gemma4E2b:
        return recommendedGemma4Kv(
          highContext: highContext,
          totalMemMb: totalMemMb,
        );
    }
  }

  static int softLimit(MessageLimitTier tier, {bool hasAttachments = false}) {
    final base = switch (tier) {
      MessageLimitTier.fast => 800,
      MessageLimitTier.medium => 2000,
      MessageLimitTier.large => 12000,
    };
    if (hasAttachments) return (base * 0.5).round();

    return base;
  }

  static int hardLimit(MessageLimitTier tier, {bool hasAttachments = false}) {
    final base = switch (tier) {
      MessageLimitTier.fast => 1500,
      MessageLimitTier.medium => 4000,
      MessageLimitTier.large => 24000,
    };
    if (hasAttachments) return (base * 0.5).round();

    return base;
  }

  static int estimateTokens(String text) => (text.length / 4).round();

  static int charsFromTokens(int tokens) => tokens * 4;

  /// Max user characters after reserving system/RAG/history overhead.
  static int maxUserCharsForInference({
    required NovaModel effectiveModel,
    int historyTokenEstimate = 0,
    int ragTokenEstimate = 0,
    int systemPromptTokenEstimate = 0,
    bool hasAttachments = false,
    bool highContext = false,
    bool hasVisionImage = false,
  }) {
    final kvLimit = kvTokenLimitFor(effectiveModel, highContext: highContext);
    final ratio = highContext ? highContextBudgetRatio : contextBudgetRatio;
    final usableBudget =
        (kvLimit * ratio).round() - safetyMarginFor(effectiveModel);

    var reserved = historyTokenEstimate + ragTokenEstimate;
    reserved += systemPromptTokenEstimate > 0
        ? systemPromptTokenEstimate
        : systemPromptOverheadTokens;
    if (effectiveModel == NovaModel.gemma4E2b) {
      reserved += gemma4JinjaOverheadTokens;
    }
    if (hasVisionImage) {
      reserved += visionImageTokenEstimate;
    } else if (hasAttachments) {
      reserved += 200;
    }

    final remainingTokens = usableBudget - reserved;
    if (remainingTokens <= 0) return exhaustedBudgetFloorChars;

    final charCap = charsFromTokens(remainingTokens);
    final tier = tierFor(model: effectiveModel, highContext: highContext);
    final tierCap = hardLimit(tier, hasAttachments: hasAttachments);

    return charCap < tierCap ? charCap : tierCap;
  }

  static int softUserCharsForInference({
    required NovaModel effectiveModel,
    int historyTokenEstimate = 0,
    int ragTokenEstimate = 0,
    int systemPromptTokenEstimate = 0,
    bool hasAttachments = false,
    bool highContext = false,
    bool hasVisionImage = false,
  }) {
    final hard = maxUserCharsForInference(
      effectiveModel: effectiveModel,
      historyTokenEstimate: historyTokenEstimate,
      ragTokenEstimate: ragTokenEstimate,
      systemPromptTokenEstimate: systemPromptTokenEstimate,
      hasAttachments: hasAttachments,
      highContext: highContext,
      hasVisionImage: hasVisionImage,
    );

    return (hard * 0.65).round();
  }

  /// Returns an error message when [text] exceeds the hard cap, else null.
  static String? validateLength({
    required String text,
    NovaModel? model,
    bool isCustomModel = false,
    bool hasAttachments = false,
    bool isAutoMode = false,
    NovaModel? effectiveModel,
  }) {
    final resolved = effectiveModel ?? model;
    final tier = effectiveTier(
      selectedModel: model,
      isAutoMode: isAutoMode,
      isCustomModel: isCustomModel,
      effectiveModel: resolved,
    );
    final hard = hardLimit(tier, hasAttachments: hasAttachments);
    if (text.length <= hard) return null;

    return 'Message is too long (${text.length} characters). '
        'Maximum for this model is $hard characters. '
        'Shorten your message or remove attachments.';
  }

  /// Token-budget validation for inference (system + RAG + history overhead).
  static String? validateTokenBudget({
    required String text,
    required NovaModel effectiveModel,
    int historyTokenEstimate = 0,
    int ragTokenEstimate = 0,
    int systemPromptTokenEstimate = 0,
    bool hasAttachments = false,
    bool highContext = false,
    bool hasVisionImage = false,
  }) {
    final maxChars = maxUserCharsForInference(
      effectiveModel: effectiveModel,
      historyTokenEstimate: historyTokenEstimate,
      ragTokenEstimate: ragTokenEstimate,
      systemPromptTokenEstimate: systemPromptTokenEstimate,
      hasAttachments: hasAttachments,
      highContext: highContext,
      hasVisionImage: hasVisionImage,
    );
    if (text.length <= maxChars) return null;

    final kvLimit = kvTokenLimitFor(effectiveModel, highContext: highContext);
    final queryTokens = estimateTokens(text);

    return 'Prompt too large (~$queryTokens tokens, KV limit $kvLimit). '
        'Maximum user message is about $maxChars characters for '
        '${effectiveModel.displayName}. Shorten your message or start a new chat.';
  }

  static bool isOverSoftLimit({
    required String text,
    NovaModel? model,
    bool isCustomModel = false,
    bool hasAttachments = false,
    bool isAutoMode = false,
    NovaModel? effectiveModel,
    int historyTokenEstimate = 0,
    int ragTokenEstimate = 0,
    int systemPromptTokenEstimate = 0,
    bool highContext = false,
    bool hasVisionImage = false,
  }) {
    final resolved = effectiveModel ?? model;
    if (resolved != null) {
      final soft = softUserCharsForInference(
        effectiveModel: resolved,
        historyTokenEstimate: historyTokenEstimate,
        ragTokenEstimate: ragTokenEstimate,
        systemPromptTokenEstimate: systemPromptTokenEstimate,
        hasAttachments: hasAttachments,
        highContext: highContext,
        hasVisionImage: hasVisionImage,
      );

      return text.length > soft;
    }

    final tier = effectiveTier(
      selectedModel: model,
      isAutoMode: isAutoMode,
      isCustomModel: isCustomModel,
    );
    final soft = softLimit(tier, hasAttachments: hasAttachments);

    return text.length > soft;
  }

  /// Pre-flight estimate of the full prompt's token cost.
  ///
  /// Combines system prompt, RAG, history, attachment context and the new
  /// query into a single number using real-token ratios. Returns null if the
  /// result fits comfortably under the KV ceiling.
  ///
  /// Used by the orchestrator before `addQuery` to decide whether to
  /// auto-compact or surface a "context near limit" warning.
  static ContextBudgetEstimate estimatePromptTokens({
    required NovaModel model,
    required String systemPrompt,
    required String query,
    String ragContext = '',
    String attachmentContext = '',
    int historyTokenEstimate = 0,
    bool hasVisionImage = false,
    bool highContext = false,
    bool textToolPrompt = false,
    int toolsCount = 0,
  }) {
    final kvLimit = kvTokenLimitFor(model, highContext: highContext);
    final ratio = highContext ? highContextBudgetRatio : contextBudgetRatio;
    final ceiling = (kvLimit * ratio).round();

    final systemTokens = estimateRealTokens(systemPrompt, model: model);
    final ragTokens = estimateRealTokens(ragContext, model: model);
    final attachmentTokens = estimateRealTokens(
      attachmentContext,
      model: model,
    );
    final queryTokens = estimateRealTokens(query, model: model);

    final visionTokens = hasVisionImage ? visionImageTokenEstimate : 0;

    final overhead = computedOverheadFor(
      model,
      systemPromptChars: systemPrompt.length,
      toolsCount: toolsCount,
      textToolPrompt: textToolPrompt,
      hasRag: ragContext.trim().isNotEmpty,
      hasAttachments: attachmentContext.trim().isNotEmpty,
    );

    final total =
        systemTokens +
        ragTokens +
        attachmentTokens +
        visionTokens +
        historyTokenEstimate +
        queryTokens +
        overhead;

    return ContextBudgetEstimate(
      estimatedTokens: total,
      kvLimit: kvLimit,
      usableCeiling: ceiling,
      systemPromptTokens: systemTokens,
      queryTokens: queryTokens,
      historyTokens: historyTokenEstimate,
      ragTokens: ragTokens,
      attachmentTokens: attachmentTokens,
      visionTokens: visionTokens,
      overheadTokens: overhead,
    );
  }
}

/// Result of [MessageLimits.estimatePromptTokens].
///
/// Exposes both the raw estimate and the KV ceiling so the UI can show a
/// progress bar ("78% of context used") and the orchestrator can decide
/// whether to auto-compact before `addQuery`.
class ContextBudgetEstimate {
  ContextBudgetEstimate({
    required this.estimatedTokens,
    required this.kvLimit,
    required this.usableCeiling,
    required this.systemPromptTokens,
    required this.queryTokens,
    required this.historyTokens,
    required this.ragTokens,
    required this.attachmentTokens,
    required this.visionTokens,
    required this.overheadTokens,
  });

  /// Total estimated tokens across system + RAG + history + query + overhead.
  final int estimatedTokens;

  /// Hard KV ceiling reported by [MessageLimits.kvTokenLimitFor].
  final int kvLimit;

  /// Soft ceiling the orchestrator aims to stay under (kvLimit * ratio).
  final int usableCeiling;

  final int systemPromptTokens;
  final int queryTokens;
  final int historyTokens;
  final int ragTokens;
  final int attachmentTokens;
  final int visionTokens;
  final int overheadTokens;

  /// Fraction of the soft ceiling used (0.0–1.0+, >1.0 means overflow).
  double get usageRatio =>
      usableCeiling <= 0 ? 1.0 : estimatedTokens / usableCeiling;

  /// True when the prompt already exceeds the KV hard cap. The orchestrator
  /// should auto-compact or refuse rather than stream into the native
  /// engine.
  bool get isOverflow => estimatedTokens > kvLimit;

  /// True when within 8 % of the soft ceiling — good trigger for the
  /// "context near limit" banner.
  bool get isNearLimit => usageRatio >= 0.92;

  Map<String, Object?> toJson() => {
    'estimatedTokens': estimatedTokens,
    'kvLimit': kvLimit,
    'usableCeiling': usableCeiling,
    'systemPromptTokens': systemPromptTokens,
    'queryTokens': queryTokens,
    'historyTokens': historyTokens,
    'ragTokens': ragTokens,
    'attachmentTokens': attachmentTokens,
    'visionTokens': visionTokens,
    'overheadTokens': overheadTokens,
    'usageRatio': usageRatio.toStringAsFixed(3),
    'isOverflow': isOverflow,
    'isNearLimit': isNearLimit,
  };
}

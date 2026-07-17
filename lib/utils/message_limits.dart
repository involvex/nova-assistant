import 'package:flutter/foundation.dart';

import 'package:nova_assistant/models/model_info.dart';

enum MessageLimitTier { fast, medium, large }

/// Model-aware character limits for chat input stability.
class MessageLimits {
  const MessageLimits._();

  static const contextBudgetRatio = 0.6;
  static const highContextBudgetRatio = 0.7;

  /// Fixed token overhead baked into Gemma 4 sessions (jinja FC template, etc.).
  static const gemma4JinjaOverheadTokens = 350;

  /// Typical system prompt + role + identity overhead.
  static const systemPromptOverheadTokens = 220;

  static const exhaustedBudgetFloorChars = 400;

  static MessageLimitTier tierFor({
    NovaModel? model,
    bool isCustomModel = false,
  }) {
    if (isCustomModel) return MessageLimitTier.large;
    if (model == null || model == NovaModel.smollm) {
      return MessageLimitTier.fast;
    }
    if (model == NovaModel.fastvlm || model == NovaModel.gemma3_1b) {
      return MessageLimitTier.medium;
    }
    if (model == NovaModel.gemma4E2b &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return MessageLimitTier.medium;
    }

    return MessageLimitTier.large;
  }

  /// Resolves the tier used for limits when Auto mode forces a heavy model.
  static MessageLimitTier effectiveTier({
    NovaModel? selectedModel,
    bool isAutoMode = false,
    bool isCustomModel = false,
    NovaModel? effectiveModel,
  }) {
    if (isCustomModel) return MessageLimitTier.large;
    final resolved = effectiveModel ?? selectedModel;
    if (resolved != null) {
      return tierFor(model: resolved, isCustomModel: false);
    }
    if (isAutoMode) {
      return tierFor(model: NovaModel.gemma4E2b, isCustomModel: false);
    }

    return MessageLimitTier.fast;
  }

  static int kvTokenLimitFor(
    NovaModel model, {
    bool highContext = false,
  }) {
    switch (model) {
      case NovaModel.smollm:
        return 512;
      case NovaModel.fastvlm:
        return 1024;
      case NovaModel.gemma3_1b:
        return 2048;
      case NovaModel.gemma4E2b:
        if (highContext) return 4096;
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          return 2048;
        }

        return 4096;
    }
  }

  static int softLimit(MessageLimitTier tier, {bool hasAttachments = false}) {
    final base = switch (tier) {
      MessageLimitTier.fast => 800,
      MessageLimitTier.medium => 2000,
      MessageLimitTier.large => 4000,
    };
    if (hasAttachments) return (base * 0.5).round();

    return base;
  }

  static int hardLimit(MessageLimitTier tier, {bool hasAttachments = false}) {
    final base = switch (tier) {
      MessageLimitTier.fast => 1500,
      MessageLimitTier.medium => 4000,
      MessageLimitTier.large => 8000,
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
    bool hasAttachments = false,
    bool highContext = false,
  }) {
    final kvLimit = kvTokenLimitFor(
      effectiveModel,
      highContext: highContext,
    );
    final ratio = highContext ? highContextBudgetRatio : contextBudgetRatio;
    final usableBudget = (kvLimit * ratio).round();

    var reserved = systemPromptOverheadTokens + historyTokenEstimate;
    if (effectiveModel == NovaModel.gemma4E2b) {
      reserved += gemma4JinjaOverheadTokens;
    }
    reserved += ragTokenEstimate;
    if (hasAttachments) reserved += 200;

    final remainingTokens = usableBudget - reserved;
    if (remainingTokens <= 0) return exhaustedBudgetFloorChars;

    final charCap = charsFromTokens(remainingTokens);
    final tier = highContext && effectiveModel == NovaModel.gemma4E2b
        ? MessageLimitTier.large
        : tierFor(model: effectiveModel);
    final tierCap = hardLimit(tier, hasAttachments: hasAttachments);

    return charCap < tierCap ? charCap : tierCap;
  }

  static int softUserCharsForInference({
    required NovaModel effectiveModel,
    int historyTokenEstimate = 0,
    int ragTokenEstimate = 0,
    bool hasAttachments = false,
    bool highContext = false,
  }) {
    final hard = maxUserCharsForInference(
      effectiveModel: effectiveModel,
      historyTokenEstimate: historyTokenEstimate,
      ragTokenEstimate: ragTokenEstimate,
      hasAttachments: hasAttachments,
      highContext: highContext,
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
    bool hasAttachments = false,
    bool highContext = false,
  }) {
    final maxChars = maxUserCharsForInference(
      effectiveModel: effectiveModel,
      historyTokenEstimate: historyTokenEstimate,
      ragTokenEstimate: ragTokenEstimate,
      hasAttachments: hasAttachments,
      highContext: highContext,
    );
    if (text.length <= maxChars) return null;

    final kvLimit = kvTokenLimitFor(
      effectiveModel,
      highContext: highContext,
    );
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
    bool highContext = false,
  }) {
    final resolved = effectiveModel ?? model;
    if (resolved != null) {
      final soft = softUserCharsForInference(
        effectiveModel: resolved,
        historyTokenEstimate: historyTokenEstimate,
        ragTokenEstimate: ragTokenEstimate,
        hasAttachments: hasAttachments,
        highContext: highContext,
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
}

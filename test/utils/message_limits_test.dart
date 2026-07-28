import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/utils/message_limits.dart';

void main() {
  group('MessageLimits', () {
    setUp(() {
      MessageLimits.setDeviceTotalMemMb(null);
    });

    tearDown(() {
      MessageLimits.setDeviceTotalMemMb(null);
    });

    test('SmolLM uses fast tier limits', () {
      final tier = MessageLimits.tierFor(model: NovaModel.smollm);
      expect(tier, MessageLimitTier.fast);
      expect(MessageLimits.hardLimit(tier), 1500);
      expect(MessageLimits.softLimit(tier), 800);
    });

    test('Gemma 3 uses medium tier limits', () {
      final tier = MessageLimits.tierFor(model: NovaModel.gemma3_1b);
      expect(tier, MessageLimitTier.medium);
      expect(MessageLimits.hardLimit(tier), 4000);
    });

    test('custom model uses large tier', () {
      final tier = MessageLimits.tierFor(isCustomModel: true);
      expect(tier, MessageLimitTier.large);
      expect(MessageLimits.hardLimit(tier), 24000);
    });

    test('Auto mode effective tier uses Gemma 4 not fast', () {
      final tier = MessageLimits.effectiveTier(isAutoMode: true);
      expect(tier, isNot(MessageLimitTier.fast));
    });

    test('attachments halve limits', () {
      final tier = MessageLimitTier.medium;
      expect(MessageLimits.hardLimit(tier, hasAttachments: true), 2000);
    });

    test('validateLength returns error when over hard cap', () {
      final text = 'a' * 2000;
      final error = MessageLimits.validateLength(
        text: text,
        model: NovaModel.smollm,
      );
      expect(error, isNotNull);
      expect(error, contains('too long'));
    });

    test('validateTokenBudget rejects long Gemma 4 query', () {
      final text = 'a' * 20000;
      final error = MessageLimits.validateTokenBudget(
        text: text,
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      expect(error, isNotNull);
      expect(error, contains('KV limit'));
    });

    test('maxUserCharsForInference is lower than raw large hard cap', () {
      final maxChars = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      expect(
        maxChars,
        lessThanOrEqualTo(MessageLimits.hardLimit(MessageLimitTier.large)),
      );
      expect(maxChars, greaterThan(MessageLimits.exhaustedBudgetFloorChars));
    });

    test('estimateTokens approximates length / 4', () {
      expect(MessageLimits.estimateTokens('abcd'), 1);
      expect(MessageLimits.estimateTokens('a' * 400), 100);
    });

    test('kvTokenLimitFor SmolLM is 1024', () {
      expect(MessageLimits.kvTokenLimitFor(NovaModel.smollm), 1024);
    });

    test('kvTokenLimitFor Gemma 4 unknown RAM defaults to 4096', () {
      MessageLimits.setDeviceTotalMemMb(null);
      expect(
        MessageLimits.kvTokenLimitFor(NovaModel.gemma4E2b, highContext: false),
        4096,
      );
    });

    test('kvTokenLimitFor Gemma 4 highContext unknown RAM is 8192', () {
      MessageLimits.setDeviceTotalMemMb(null);
      expect(
        MessageLimits.kvTokenLimitFor(NovaModel.gemma4E2b, highContext: true),
        8192,
      );
    });

    test('recommendedGemma4Kv uses 16K base on 12 GB devices', () {
      expect(
        MessageLimits.recommendedGemma4Kv(
          highContext: false,
          totalMemMb: 12288,
        ),
        16384,
      );
      expect(
        MessageLimits.recommendedGemma4Kv(highContext: true, totalMemMb: 12288),
        MessageLimits.gemma4NativeMaxContext,
      );
    });

    test('recommendedGemma4Kv keeps low-RAM phones conservative', () {
      expect(
        MessageLimits.recommendedGemma4Kv(highContext: false, totalMemMb: 4096),
        2048,
      );
    });

    test('clampCustomContextTokens bounds presets', () {
      expect(MessageLimits.clampCustomContextTokens(100), 512);
      expect(
        MessageLimits.clampCustomContextTokens(99999),
        MessageLimits.gemma4NativeMaxContext,
      );
      expect(MessageLimits.clampCustomContextTokens(8192), 8192);
    });

    test('highContext empty session allows at least 4000 user chars', () {
      MessageLimits.setDeviceTotalMemMb(null);
      final maxChars = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: true,
      );
      expect(maxChars, greaterThanOrEqualTo(4000));
    });

    test('vision image reserves more budget than text-only', () {
      final without = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: true,
      );
      final withVision = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: true,
        hasVisionImage: true,
      );
      expect(withVision, lessThan(without));
    });

    test('large system prompt reduces user char budget', () {
      final roomy = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: true,
        systemPromptTokenEstimate: 200,
        hasVisionImage: false,
      );
      final tight = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: true,
        systemPromptTokenEstimate: 1500,
        hasVisionImage: true,
      );
      expect(tight, lessThan(roomy));
      expect(tight, greaterThan(MessageLimits.exhaustedBudgetFloorChars));
    });

    test('low context still protects mid-range RAM', () {
      final maxChars = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      // Unknown-RAM default is 4096 KV — still admits a real user message.
      expect(maxChars, greaterThanOrEqualTo(800));
    });

    test('12 GB device empty session allows long messages', () {
      MessageLimits.setDeviceTotalMemMb(null);
      final unknownRam = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      MessageLimits.setDeviceTotalMemMb(12288);
      final on12gb = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      expect(on12gb, greaterThanOrEqualTo(unknownRam));
      expect(on12gb, greaterThanOrEqualTo(4000));
    });

    test('estimateRealTokens returns higher count than chars/4 for code', () {
      const code = 'const x = 42; if (x > 0) return x;';
      final legacy = MessageLimits.estimateTokens(code);
      final real = MessageLimits.estimateRealTokens(
        code,
        model: NovaModel.gemma4E2b,
      );
      expect(real, greaterThan(legacy));
    });

    test('estimateRealTokens counts digits more aggressively', () {
      final digits = '0' * 100;
      final legacy = MessageLimits.estimateTokens(digits);
      final real = MessageLimits.estimateRealTokens(
        digits,
        model: NovaModel.gemma4E2b,
      );
      expect(real, greaterThan(legacy));
    });

    test('safetyMarginFor Gemma 4 is larger than the base margin', () {
      expect(
        MessageLimits.safetyMarginFor(NovaModel.gemma4E2b),
        greaterThan(MessageLimits.safetyMarginFor(NovaModel.smollm)),
      );
    });

    test('computedOverheadFor scales with system prompt length', () {
      final shortOverhead = MessageLimits.computedOverheadFor(
        NovaModel.gemma4E2b,
        systemPromptChars: 500,
      );
      final longOverhead = MessageLimits.computedOverheadFor(
        NovaModel.gemma4E2b,
        systemPromptChars: 3000,
      );
      expect(longOverhead, greaterThan(shortOverhead));
    });

    test('computedOverheadFor includes tool schema cost', () {
      final none = MessageLimits.computedOverheadFor(NovaModel.gemma4E2b);
      final withTools = MessageLimits.computedOverheadFor(
        NovaModel.gemma4E2b,
        toolsCount: 16,
      );
      expect(withTools - none, greaterThanOrEqualTo(400));
    });

    test('computedOverheadFor includes jinja cost for Gemma 4', () {
      final gemma4 = MessageLimits.computedOverheadFor(NovaModel.gemma4E2b);
      final smollm = MessageLimits.computedOverheadFor(NovaModel.smollm);
      expect(gemma4 - smollm, greaterThanOrEqualTo(400));
    });

    test('estimatePromptTokens flags near-limit prompts', () {
      MessageLimits.setDeviceTotalMemMb(null);
      final estimate = MessageLimits.estimatePromptTokens(
        model: NovaModel.gemma4E2b,
        systemPrompt: 'x' * 12000,
        query: 'a' * 20000,
        highContext: true,
      );
      expect(estimate.isOverflow, isTrue);
      expect(estimate.isNearLimit, isTrue);
      expect(estimate.usageRatio, greaterThan(1.0));
    });

    test('estimatePromptTokens fits a small prompt', () {
      final estimate = MessageLimits.estimatePromptTokens(
        model: NovaModel.gemma4E2b,
        systemPrompt: 'You are Nova.',
        query: 'Hi',
        highContext: true,
      );
      expect(estimate.isOverflow, isFalse);
      expect(estimate.estimatedTokens, lessThan(estimate.kvLimit));
    });

    test('estimatePromptTokens records per-section token counts', () {
      final estimate = MessageLimits.estimatePromptTokens(
        model: NovaModel.gemma4E2b,
        systemPrompt: 'system prompt',
        query: 'hello',
        ragContext: 'rag context',
        attachmentContext: 'attach',
        hasVisionImage: true,
        highContext: true,
        textToolPrompt: true,
        toolsCount: 5,
      );
      expect(estimate.systemPromptTokens, greaterThan(0));
      expect(estimate.queryTokens, greaterThan(0));
      expect(estimate.ragTokens, greaterThan(0));
      expect(estimate.attachmentTokens, greaterThan(0));
      expect(estimate.visionTokens, MessageLimits.visionImageTokenEstimate);
      expect(estimate.overheadTokens, greaterThan(400));
    });
  });
}

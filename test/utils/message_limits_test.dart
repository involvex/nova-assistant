import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/utils/message_limits.dart';

void main() {
  group('MessageLimits', () {
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
      expect(MessageLimits.hardLimit(tier), 8000);
    });

    test('Auto mode effective tier uses Gemma 4 not fast', () {
      final tier = MessageLimits.effectiveTier(isAutoMode: true);
      expect(tier, MessageLimitTier.medium);
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
      final text = 'a' * 5000;
      final error = MessageLimits.validateTokenBudget(
        text: text,
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      expect(error, isNotNull);
      expect(error, contains('KV limit'));
    });

    test('maxUserCharsForInference is lower than raw medium hard cap', () {
      final maxChars = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      expect(
        maxChars,
        lessThan(MessageLimits.hardLimit(MessageLimitTier.medium)),
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

    test('kvTokenLimitFor Gemma 4 returns 2048 on all platforms in tests', () {
      expect(
        MessageLimits.kvTokenLimitFor(NovaModel.gemma4E2b, highContext: false),
        2048,
      );
    });

    test('kvTokenLimitFor Gemma 4 highContext is 4096', () {
      expect(
        MessageLimits.kvTokenLimitFor(NovaModel.gemma4E2b, highContext: true),
        4096,
      );
    });

    test('highContext empty session allows at least 4000 user chars', () {
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
      final tight = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: true,
        systemPromptTokenEstimate: 1500,
        hasVisionImage: true,
      );
      expect(
        tight,
        lessThanOrEqualTo(MessageLimits.exhaustedBudgetFloorChars * 4),
      );
    });

    test('low context still protects mid-range RAM', () {
      final maxChars = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        highContext: false,
      );
      expect(maxChars, greaterThanOrEqualTo(1500));
    });
  });
}

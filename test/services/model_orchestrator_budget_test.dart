import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/utils/message_limits.dart';

void main() {
  group('ModelOrchestrator budget helpers', () {
    test('predictEffectiveModel uses primary heavy when forced', () {
      final model = ModelOrchestrator.instance.predictEffectiveModel(
        query: 'hi',
        forcePrimaryModel: true,
      );
      expect(model, NovaModel.gemma4E2b);
    });

    test('isBusy is false when idle', () {
      expect(ModelOrchestrator.instance.isBusy, isFalse);
    });

    test('resetInferenceSession clears streaming flags', () async {
      await ModelOrchestrator.instance.resetInferenceSession();
      expect(ModelOrchestrator.instance.isStreaming, isFalse);
      expect(ModelOrchestrator.instance.isLoadingModel, isFalse);
      expect(ModelOrchestrator.instance.isModelLoaded, isFalse);
    });
  });

  group('MessageLimits token budget', () {
    test('high RAG overhead reduces allowed user chars', () {
      final lowRag = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        ragTokenEstimate: 0,
      );
      final highRag = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        ragTokenEstimate: 700,
      );
      expect(highRag, lessThan(lowRag));
    });
  });
}

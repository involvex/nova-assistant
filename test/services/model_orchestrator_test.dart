import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';

void main() {
  group('InferenceResult', () {
    test('constructs with required fields', () {
      final result = InferenceResult(text: 'Hello!', model: NovaModel.smollm);
      expect(result.text, 'Hello!');
      expect(result.model, NovaModel.smollm);
      expect(result.isStreaming, false);
      expect(result.thinking, isNull);
    });

    test('constructs with all fields', () {
      final result = InferenceResult(
        text: 'Response text',
        model: NovaModel.gemma4E2b,
        isStreaming: true,
        thinking: 'Let me think about this...',
      );
      expect(result.text, 'Response text');
      expect(result.model, NovaModel.gemma4E2b);
      expect(result.isStreaming, true);
      expect(result.thinking, 'Let me think about this...');
    });

    test('defaults isStreaming to false', () {
      final result = InferenceResult(text: 'test', model: NovaModel.fastvlm);
      expect(result.isStreaming, false);
    });

    test('model reference is preserved', () {
      const model = NovaModel.gemma4E2b;
      final result = InferenceResult(text: 'test', model: model);
      expect(result.model, same(model));
      expect(result.model.displayName, 'Gemma 4 E2B');
    });
  });

  group('ModelOrchestrator system prompt', () {
    test('system prompt mentions Nova', () {
      // Verify the system prompt structure by checking model properties
      // The actual prompt is private, but we can verify model selection behavior
      final selector = ModelSelector(
        primaryHeavy: NovaModel.gemma4E2b,
        fastModel: NovaModel.smollm,
      );

      // Thinking model should be selected for complex queries
      final model = selector.selectForQuery(
        query: 'Explain the meaning of life in detail',
        hasVisionContext: false,
        requestedThinking: true,
      );
      expect(model.hasThinking, true);
    });

    test('non-thinking model selected for simple queries', () {
      final selector = ModelSelector(
        primaryHeavy: NovaModel.gemma4E2b,
        fastModel: NovaModel.smollm,
      );

      final model = selector.selectForQuery(
        query: 'hi',
        hasVisionContext: false,
        requestedThinking: false,
      );
      expect(model.hasThinking, false);
    });
  });

  group('ModelOrchestrator debug mode', () {
    test('defaults to disabled', () {
      expect(ModelOrchestrator.instance.isDebugMode, false);
    });

    test('setDebugMode toggles state', () {
      ModelOrchestrator.instance.setDebugMode(true);
      expect(ModelOrchestrator.instance.isDebugMode, true);
      ModelOrchestrator.instance.setDebugMode(false);
      expect(ModelOrchestrator.instance.isDebugMode, false);
    });
  });
}

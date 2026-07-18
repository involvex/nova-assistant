import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';

void main() {
  group('NovaModel', () {
    test('has correct display names', () {
      expect(NovaModel.smollm.displayName, 'SmolLM-135M');
      expect(NovaModel.fastvlm.displayName, 'FastVLM-0.5B');
      expect(NovaModel.gemma3_1b.displayName, 'Gemma 3 1B');
      expect(NovaModel.gemma4E2b.displayName, 'Gemma 4 E2B');
    });

    test('has correct size values', () {
      expect(NovaModel.smollm.sizeMB, 135);
      expect(NovaModel.fastvlm.sizeMB, 500);
      expect(NovaModel.gemma3_1b.sizeMB, 500);
      expect(NovaModel.gemma4E2b.sizeMB, 2400);
    });

    test('has vision flag set correctly', () {
      expect(NovaModel.smollm.hasVision, false);
      expect(NovaModel.fastvlm.hasVision, true);
      expect(NovaModel.gemma3_1b.hasVision, false);
      expect(NovaModel.gemma4E2b.hasVision, true);
    });

    test('has thinking flag set correctly', () {
      expect(NovaModel.smollm.hasThinking, false);
      expect(NovaModel.fastvlm.hasThinking, false);
      expect(NovaModel.gemma3_1b.hasThinking, false);
      expect(NovaModel.gemma4E2b.hasThinking, true);
    });

    test('SmolLM does not advertise function calling', () {
      expect(NovaModel.smollm.supportsFunctionCalling, false);
      expect(NovaModel.gemma3_1b.supportsFunctionCalling, true);
    });

    test('enum has exactly 4 values', () {
      expect(NovaModel.values.length, 4);
    });
  });

  group('ModelSelector', () {
    late ModelSelector selector;

    setUp(() {
      selector = ModelSelector(
        primaryHeavy: NovaModel.gemma4E2b,
        fastModel: NovaModel.smollm,
      );
    });

    group('selectForQuery', () {
      test('returns vision model when screenshot provided', () {
        final result = selector.selectForQuery(
          query: 'hello',
          hasVisionContext: true,
          requestedThinking: false,
        );
        expect(result, NovaModel.gemma4E2b);
      });

      test('falls back to fast model if primary has no vision', () {
        final noVisionSelector = ModelSelector(
          primaryHeavy: NovaModel.gemma3_1b,
          fastModel: NovaModel.fastvlm,
        );
        final result = noVisionSelector.selectForQuery(
          query: 'hello',
          hasVisionContext: true,
          requestedThinking: false,
        );
        expect(result, NovaModel.fastvlm);
      });

      test('returns fast model for short simple query', () {
        final result = selector.selectForQuery(
          query: 'hello world',
          hasVisionContext: false,
          requestedThinking: false,
        );
        expect(result, NovaModel.smollm);
      });

      test('returns fast model for exactly 8 words', () {
        final result = selector.selectForQuery(
          query: 'one two three four five six seven eight',
          hasVisionContext: false,
          requestedThinking: false,
        );
        expect(result, NovaModel.smollm);
      });

      test('returns heavy model for query longer than 8 words', () {
        final result = selector.selectForQuery(
          query: 'one two three four five six seven eight nine',
          hasVisionContext: false,
          requestedThinking: false,
        );
        expect(result, NovaModel.gemma4E2b);
      });

      test('returns heavy model when thinking requested', () {
        final result = selector.selectForQuery(
          query: 'hello',
          hasVisionContext: false,
          requestedThinking: true,
        );
        expect(result, NovaModel.gemma4E2b);
      });

      test('returns heavy model for complex query with thinking', () {
        final result = selector.selectForQuery(
          query: 'explain quantum computing in detail please',
          hasVisionContext: false,
          requestedThinking: true,
        );
        expect(result, NovaModel.gemma4E2b);
      });

      test('returns heavy model as default for long query', () {
        final result = selector.selectForQuery(
          query: 'this is a longer query that should definitely use the heavy model for processing',
          hasVisionContext: false,
          requestedThinking: false,
        );
        expect(result, NovaModel.gemma4E2b);
      });
    });
  });

  group('ModelHuggingFaceURLs', () {
    test('urlFor returns correct URL for each model', () {
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.smollm),
        ModelHuggingFaceURLs.smollm,
      );
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.fastvlm),
        ModelHuggingFaceURLs.fastvlm,
      );
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.gemma3_1b),
        ModelHuggingFaceURLs.gemma3_1b,
      );
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.gemma4E2b),
        ModelHuggingFaceURLs.gemma4E2b,
      );
    });

    test('URLs match their expected file extensions', () {
      expect(ModelHuggingFaceURLs.smollm, endsWith('.task'));
      expect(ModelHuggingFaceURLs.fastvlm, endsWith('.litertlm'));
      expect(ModelHuggingFaceURLs.gemma3_1b, endsWith('.litertlm'));
      expect(ModelHuggingFaceURLs.gemma4E2b, endsWith('.litertlm'));
    });

    test('all URLs use HTTPS', () {
      expect(ModelHuggingFaceURLs.smollm, startsWith('https://'));
      expect(ModelHuggingFaceURLs.fastvlm, startsWith('https://'));
      expect(ModelHuggingFaceURLs.gemma3_1b, startsWith('https://'));
      expect(ModelHuggingFaceURLs.gemma4E2b, startsWith('https://'));
    });

    test('all URLs point to huggingface.co', () {
      expect(ModelHuggingFaceURLs.smollm, contains('huggingface.co'));
      expect(ModelHuggingFaceURLs.fastvlm, contains('huggingface.co'));
      expect(ModelHuggingFaceURLs.gemma3_1b, contains('huggingface.co'));
      expect(ModelHuggingFaceURLs.gemma4E2b, contains('huggingface.co'));
    });
  });
}

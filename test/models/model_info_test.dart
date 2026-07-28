import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/litert_model_catalog.dart';
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
      // LiteRT Gemma 3 ignores native tools — text-tool path only.
      expect(NovaModel.gemma3_1b.supportsFunctionCalling, false);
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
    test('urlFor returns catalog download URLs', () {
      for (final entry in LiteRtModelCatalog.recommended) {
        expect(
          ModelHuggingFaceURLs.urlFor(entry.novaModel),
          entry.downloadUrl,
        );
      }
    });

    test('URLs match their expected file extensions', () {
      expect(ModelHuggingFaceURLs.urlFor(NovaModel.smollm), endsWith('.task'));
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.fastvlm),
        endsWith('.litertlm'),
      );
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.gemma3_1b),
        endsWith('.litertlm'),
      );
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.gemma4E2b),
        endsWith('.litertlm'),
      );
    });

    test('all URLs use HTTPS huggingface.co', () {
      for (final model in NovaModel.values) {
        final url = ModelHuggingFaceURLs.urlFor(model);
        expect(url, startsWith('https://'));
        expect(url, contains('huggingface.co'));
      }
    });
  });
}

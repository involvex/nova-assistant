import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/litert_model_catalog.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/huggingface_hub_service.dart';

void main() {
  group('HuggingfaceHubService.resolveDownloadUrl', () {
    test('builds resolve/main URL', () {
      expect(
        HuggingfaceHubService.resolveDownloadUrl(
          'litert-community/FastVLM-0.5B',
          path: 'FastVLM-0.5B.litertlm',
        ),
        'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm',
      );
    });

    test('encodes path segments', () {
      final url = HuggingfaceHubService.resolveDownloadUrl(
        'org/my model',
        path: 'subdir/file name.litertlm',
      );
      expect(url, contains('org/my%20model'));
      expect(url, contains('file%20name.litertlm'));
    });
  });

  group('HuggingfaceHubService.filterLiteRtFiles', () {
    test('keeps only litertlm and task files', () {
      final files = [
        const HfRepoFile(path: 'README.md', type: 'file'),
        const HfRepoFile(path: 'model.litertlm', type: 'file', size: 100),
        const HfRepoFile(path: 'weights.gguf', type: 'file'),
        const HfRepoFile(path: 'nested/x.task', type: 'file'),
        const HfRepoFile(path: 'folder', type: 'directory'),
      ];
      final filtered = HuggingfaceHubService.filterLiteRtFiles(files);
      expect(filtered.map((f) => f.path), ['model.litertlm', 'nested/x.task']);
    });

    test('preferLitertlm drops task when litertlm exists', () {
      final files = [
        const HfRepoFile(path: 'a.task'),
        const HfRepoFile(path: 'b.litertlm'),
        const HfRepoFile(path: 'c.task'),
      ];
      final preferred = HuggingfaceHubService.preferLitertlm(
        HuggingfaceHubService.filterLiteRtFiles(files),
      );
      expect(preferred.map((f) => f.path), ['b.litertlm']);
    });
  });

  group('HuggingfaceHubService.inferInstallHints', () {
    test('detects gemma4 vision thinking and 8k context', () {
      final hints = HuggingfaceHubService.inferInstallHints(
        repoId: 'litert-community/gemma-4-E2B-it-litert-lm',
        filePath: 'gemma-4-E2B-it.litertlm',
      );
      expect(hints.modelType, ModelType.gemma4);
      expect(hints.hasVision, isTrue);
      expect(hints.hasThinking, isTrue);
      expect(hints.maxContextTokens, 8192);
      expect(hints.fileType, ModelFileType.litertlm);
    });

    test('detects gemma3', () {
      final hints = HuggingfaceHubService.inferInstallHints(
        repoId: 'litert-community/Gemma3-1B-IT',
        filePath: 'gemma3-1b-it-int4.litertlm',
      );
      expect(hints.modelType, ModelType.gemmaIt);
      expect(hints.maxContextTokens, 4096);
    });

    test('fastvlm is general with vision', () {
      final hints = HuggingfaceHubService.inferInstallHints(
        repoId: 'litert-community/FastVLM-0.5B',
        filePath: 'FastVLM-0.5B.litertlm',
        tags: ['vision'],
      );
      expect(hints.modelType, ModelType.general);
      expect(hints.hasVision, isTrue);
    });

    test('flags uncensored repos', () {
      final hints = HuggingfaceHubService.inferInstallHints(
        repoId: 'PeppX/gemma-4-e2b-uncensored-litertlm',
        filePath: 'gemma4_uncensored_INT4_8192.litertlm',
      );
      expect(hints.isUncensored, isTrue);
      expect(hints.modelType, ModelType.gemma4);
      expect(hints.fileType, ModelFileType.litertlm);
    });

    test('clean repos are not flagged uncensored', () {
      final hints = HuggingfaceHubService.inferInstallHints(
        repoId: 'litert-community/SmolLM-135M-Instruct',
        filePath: 'SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
      );
      expect(hints.isUncensored, isFalse);
    });
  });

  group('HuggingfaceHubService.isUncensoredBlob', () {
    test('matches known keywords', () {
      expect(
        HuggingfaceHubService.isUncensoredBlob(
          'PeppX/gemma-4-e2b-uncensored-litertlm uncensored gemma4',
        ),
        isTrue,
      );
      expect(
        HuggingfaceHubService.isUncensoredBlob(
          'nqd145/Gemma-4-E2B-abliterated',
        ),
        isTrue,
      );
      expect(HuggingfaceHubService.isUncensoredBlob('dolphin-mistral'), isTrue);
      expect(
        HuggingfaceHubService.isUncensoredBlob('qwen2.5-unaligned-heretic'),
        isTrue,
      );
    });

    test('ignores clean names', () {
      expect(
        HuggingfaceHubService.isUncensoredBlob(
          'litert-community/gemma-4-E2B-it-litert-lm vision thinking',
        ),
        isFalse,
      );
    });
  });

  group('HfModelHit / HfRepoFile parsing', () {
    test('parses gated flag variants', () {
      expect(HfModelHit.fromJson({'id': 'a/b', 'gated': true}).gated, isTrue);
      expect(HfModelHit.fromJson({'id': 'a/b', 'gated': 'auto'}).gated, isTrue);
      expect(HfModelHit.fromJson({'id': 'a/b', 'gated': false}).gated, isFalse);
    });

    test('parses tree entry', () {
      final f = HfRepoFile.fromJson({
        'path': 'weights/model.litertlm',
        'size': 2048,
        'type': 'file',
      });
      expect(f.fileName, 'model.litertlm');
      expect(f.size, 2048);
      expect(f.isFile, isTrue);
    });
  });

  group('LiteRtModelCatalog', () {
    test('covers all NovaModel values', () {
      for (final model in NovaModel.values) {
        expect(LiteRtModelCatalog.forNovaModel(model), isNotNull);
        expect(LiteRtModelCatalog.repoIdFor(model), contains('/'));
      }
    });

    test('ModelHuggingFaceURLs delegates to catalog', () {
      expect(
        ModelHuggingFaceURLs.urlFor(NovaModel.fastvlm),
        LiteRtModelCatalog.forNovaModel(NovaModel.fastvlm)!.downloadUrl,
      );
      expect(
        ModelHuggingFaceURLs.fileNameFor(NovaModel.gemma4E2b),
        'gemma-4-E2B-it.litertlm',
      );
      expect(
        ModelHuggingFaceURLs.requiresHuggingFaceAuth(NovaModel.gemma4E2b),
        isTrue,
      );
      expect(
        ModelHuggingFaceURLs.requiresHuggingFaceAuth(NovaModel.smollm),
        isFalse,
      );
    });
  });

  group('ModelHuggingFaceURLs.urlRequiresHuggingFaceAuth', () {
    test('official litert-community gemma assets require auth', () {
      expect(
        ModelHuggingFaceURLs.urlRequiresHuggingFaceAuth(
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'
          '/resolve/main/gemma-4-E2B-it.litertlm',
        ),
        isTrue,
      );
      expect(
        ModelHuggingFaceURLs.urlRequiresHuggingFaceAuth(
          'https://huggingface.co/litert-community/Gemma3-1B-IT'
          '/resolve/main/gemma3-1b-it-int4.litertlm',
        ),
        isTrue,
      );
    });

    test('community uncensored mirrors stay token-free', () {
      expect(
        ModelHuggingFaceURLs.urlRequiresHuggingFaceAuth(
          'https://huggingface.co/PeppX/gemma-4-e2b-uncensored-litertlm'
          '/resolve/main/gemma4_uncensored_INT4_8192.litertlm',
        ),
        isFalse,
      );
    });

    test('non-litert-community repos are never gated', () {
      expect(
        ModelHuggingFaceURLs.urlRequiresHuggingFaceAuth(
          'https://huggingface.co/some-org/gemma-4-copy/resolve/main/m.task',
        ),
        isFalse,
      );
    });
  });
}

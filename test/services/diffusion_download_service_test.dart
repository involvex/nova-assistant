import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/diffusion_model_info.dart';
import 'package:nova_assistant/utils/file_hash.dart';

void main() {
  group('DiffusionExtraAssets', () {
    test('zImageTurbo has correct tokenizer files', () {
      final assets = DiffusionModel.zImageTurbo.extraAssets;

      expect(
        assets.tokenizerFiles,
        containsAll([
          'tokenizer/vocab.json',
          'tokenizer/merges.txt',
          'tokenizer/tokenizer.json',
          'tokenizer/tokenizer_config.json',
        ]),
      );
      expect(assets.tokenizerRepoId, equals('Tongyi-MAI/Z-Image-Turbo'));
    });

    test('zImageTurbo points embed_tokens at its source shard', () {
      final assets = DiffusionModel.zImageTurbo.extraAssets;

      expect(
        assets.embedTokensSource,
        equals('text_encoder/model-00001-of-00003.safetensors'),
      );
      expect(assets.embedTokensRepoId, equals('Tongyi-MAI/Z-Image-Turbo'));
      expect(assets.embedTokensFile, equals('embed_tokens.safetensors'));
    });

    test('zImageTurbo points t_embedder at its source shard', () {
      final assets = DiffusionModel.zImageTurbo.extraAssets;

      expect(
        assets.tEmbedderSource,
        equals(
          'transformer/diffusion_pytorch_model-00001-of-00003.safetensors',
        ),
      );
      expect(assets.tEmbedderRepoId, equals('Tongyi-MAI/Z-Image-Turbo'));
      expect(assets.tEmbedderFile, equals('t_embedder.safetensors'));
    });

    test('flux2Klein has empty tokenizer files', () {
      final assets = DiffusionModel.flux2Klein.extraAssets;

      expect(assets.tokenizerFiles, isEmpty);
      expect(assets.embedTokensSource, isEmpty);
      expect(assets.tEmbedderSource, isEmpty);
    });
  });

  group('DiffusionModelExtensions', () {
    test('zImageTurbo has extraAssets', () {
      final assets = DiffusionModel.zImageTurbo.extraAssets;
      expect(assets, isNotNull);
    });

    test('flux2Klein has extraAssets', () {
      final assets = DiffusionModel.flux2Klein.extraAssets;
      expect(assets, isNotNull);
    });

    test('inferenceReady is true for zImageTurbo, false for flux', () {
      // Z-Image Turbo ships a complete native host loop (verified by the
      // fake-executor end-to-end 256px run); FLUX.2-klein is still unwired.
      expect(DiffusionModel.zImageTurbo.inferenceReady, isTrue);
      expect(DiffusionModel.flux2Klein.inferenceReady, isFalse);
    });
  });

  group('DiffusionExtraAssets.hasExtraAssets', () {
    Future<Directory> createModelDir({
      bool includeTokenizer = true,
      bool includeEmbedTokens = true,
      bool includeTEmbedder = true,
    }) async {
      final dir = await Directory.systemTemp.createTemp('zimage_test_');
      final assets = DiffusionModel.zImageTurbo.extraAssets;
      if (includeTokenizer) {
        for (final file in assets.tokenizerFiles) {
          final f = File('${dir.path}/$file');
          await f.parent.create(recursive: true);
          await f.writeAsString('{}');
        }
      }
      if (includeEmbedTokens) {
        await File('${dir.path}/${assets.embedTokensFile}')
            .writeAsString('embed');
      }
      if (includeTEmbedder) {
        await File('${dir.path}/${assets.tEmbedderFile}').writeAsString('t');
      }
      return dir;
    }

    test('returns true when all assets exist', () async {
      final dir = await createModelDir();
      try {
        final assets = DiffusionModel.zImageTurbo.extraAssets;
        expect(await assets.hasExtraAssets(dir), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns false when a tokenizer file is missing', () async {
      final dir = await createModelDir();
      try {
        final assets = DiffusionModel.zImageTurbo.extraAssets;
        await File('${dir.path}/${assets.tokenizerFiles.first}').delete();
        expect(await assets.hasExtraAssets(dir), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns false when embed_tokens is missing', () async {
      final dir = await createModelDir(includeEmbedTokens: false);
      try {
        final assets = DiffusionModel.zImageTurbo.extraAssets;
        expect(await assets.hasExtraAssets(dir), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns false when t_embedder is missing', () async {
      final dir = await createModelDir(includeTEmbedder: false);
      try {
        final assets = DiffusionModel.zImageTurbo.extraAssets;
        expect(await assets.hasExtraAssets(dir), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns false for an empty directory', () async {
      final dir = await Directory.systemTemp.createTemp('zimage_empty_');
      try {
        final assets = DiffusionModel.zImageTurbo.extraAssets;
        expect(await assets.hasExtraAssets(dir), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('DiffusionExtraAssets.verifyFilePins', () {
    DiffusionExtraAssets pinsFor({
      Map<String, int> sizes = const <String, int>{},
      Map<String, String> hashes = const <String, String>{},
    }) {
      return DiffusionExtraAssets(
        tokenizerRepoId: '',
        tokenizerFiles: const <String>[],
        embedTokensRepoId: '',
        embedTokensSource: '',
        embedTokensFile: 'e',
        tEmbedderRepoId: '',
        tEmbedderSource: '',
        tEmbedderFile: 't',
        expectedSizes: sizes,
        expectedSha256: hashes,
      );
    }

    test('passes with correct size and sha', () async {
      final dir = await Directory.systemTemp.createTemp('zimage_pins_');
      try {
        final file = File('${dir.path}/a.bin');
        await file.writeAsString('hello');
        final assets = pinsFor(
          sizes: <String, int>{'a.bin': 5},
          hashes: <String, String>{'a.bin': await sha256HexOfFile(file)},
        );
        await assets.verifyFilePins(dir);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throws on size drift', () async {
      final dir = await Directory.systemTemp.createTemp('zimage_pins_sz_');
      try {
        await File('${dir.path}/a.bin').writeAsString('hello');
        await expectLater(
          pinsFor(sizes: <String, int>{'a.bin': 999}).verifyFilePins(dir),
          throwsStateError,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throws on sha drift', () async {
      final dir = await Directory.systemTemp.createTemp('zimage_pins_hash_');
      try {
        await File('${dir.path}/a.bin').writeAsString('hello');
        await expectLater(
          pinsFor(hashes: <String, String>{'a.bin': '0' * 64})
              .verifyFilePins(dir),
          throwsStateError,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('skips unpinned entries', () async {
      final dir = await Directory.systemTemp.createTemp('zimage_pins_skip_');
      try {
        await pinsFor().verifyFilePins(dir);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}

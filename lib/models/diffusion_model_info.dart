import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nova_assistant/utils/file_hash.dart';

enum DiffusionModel {
  zImageTurbo(
    'Z-Image-Turbo-LiteRT',
    'Z-Image-Turbo',
    'litert-community/Z-Image-Turbo-LiteRT',
    9400,
  ),
  flux2Klein(
    'FLUX.2-klein-4B-LiteRT',
    'FLUX.2-klein-4B',
    'litert-community/FLUX.2-klein-4B-LiteRT',
    9600,
  );

  final String fileName;
  final String displayName;
  final String repoId;
  final int approxSizeMB;

  const DiffusionModel(
    this.fileName,
    this.displayName,
    this.repoId,
    this.approxSizeMB,
  );

  /// Weights can install while the native host loop is still unfinished.
  /// Flip via [debugForceInferenceReady] in widget tests only.
  @visibleForTesting
  static bool debugForceInferenceReady = false;

  /// Z-Image Turbo ships a complete native host loop (tokenize → embed →
  /// qwen_enc → DiT chunks → zvae), verified by the fake-executor
  /// end-to-end 256 px run (`ZImagePipelineTest`) plus 49 Kotlin unit tests.
  /// Per-device readiness is still enforced separately: installs need the
  /// graphs ([ModelManager.findDiffusionModelPath]), the extracted assets
  /// ([ModelManager.hasExtraAssets]), and the native header pre-check
  /// inside `DiffusionPipeline` fails closed with a reinstall message.
  bool get inferenceReady =>
      this == DiffusionModel.zImageTurbo || debugForceInferenceReady;

  /// User-facing reason when [inferenceReady] is false, or when extra assets
  /// are missing for a ready model.
  String get runnerNotReadyMessage => switch (this) {
    DiffusionModel.zImageTurbo =>
      'Z-Image Turbo weights are installed, but extra assets are missing. '
          'The Qwen3 tokenizer, the embed_tokens matrix, and the t_embedder '
          'MLP come from the base checkpoint — download them from Settings '
          'to enable image generation. Chat is unaffected.',
    DiffusionModel.flux2Klein =>
      'FLUX.2-klein weights are installed, but Nova cannot run them yet. '
          'The on-device diffusion runner is not wired for this LiteRT graph set.',
  };
}

enum DiffusionModelFileType {
  diffusion;

  String get extension => 'diffusion';
}

enum ImageSize {
  size256(256),
  size512(512),
  size1024(1024);

  final int pixels;
  const ImageSize(this.pixels);

  String get label => '${pixels}x$pixels';

  @override
  String toString() => label;
}

/// Additional assets needed for diffusion inference (on top of .tflite).
/// Verified against docs/z-image-turbo-litert.md:
/// - tokenizer/ (~11 MB) downloads directly.
/// - embed_tokens [151936,2560] lives inside
///   text_encoder/model-00001-of-00003.safetensors — the host only needs the
///   778 MB bf16 matrix (389 MB int8), stored locally as [embedTokensFile].
/// - t_embedder MLP (mlp.0 [1024,256] + mlp.2 [256,1024], ~2 MB fp32) lives
///   inside transformer/diffusion_pytorch_model-00001-of-00003.safetensors,
///   stored locally as [tEmbedderFile].
class DiffusionExtraAssets {
  const DiffusionExtraAssets({
    required this.tokenizerRepoId,
    required this.tokenizerFiles,
    required this.embedTokensRepoId,
    required this.embedTokensSource,
    required this.embedTokensFile,
    required this.tEmbedderRepoId,
    required this.tEmbedderSource,
    required this.tEmbedderFile,
    this.expectedSizes = const <String, int>{},
    this.expectedSha256 = const <String, String>{},
  });

  final String tokenizerRepoId;
  final List<String> tokenizerFiles;

  final String embedTokensRepoId;

  /// Upstream path of the shard containing embed_tokens.
  final String embedTokensSource;

  /// Local destination (relative to the model dir) for the extracted matrix.
  final String embedTokensFile;

  final String tEmbedderRepoId;

  /// Upstream path of the shard containing t_embedder.mlp.{0,2}.
  final String tEmbedderSource;

  /// Local destination (relative to the model dir) for the extracted MLP.
  final String tEmbedderFile;

  /// Exact byte sizes keyed by local relative path (staged shards,
  /// tokenizer files, derived files). Zero or absent entries are skipped.
  ///
  /// Pins are intentionally unpopulated for the gated `Tongyi-MAI` upstream
  /// (sizes vary by revision and must never be guessed): after one verified
  /// download, fill these from `sha256sum` output and sizes become enforced
  /// by [verifyFilePins].
  final Map<String, int> expectedSizes;

  /// Lowercase hex SHA-256 keyed by local relative path. Empty or absent
  /// entries are skipped. Same population rule as [expectedSizes].
  final Map<String, String> expectedSha256;

  /// All upstream files that must be fetched (tokenizer + source shards).
  List<String> get upstreamFiles => [
    ...tokenizerFiles,
    embedTokensSource,
    tEmbedderSource,
  ];

  /// Checks if the required extra assets exist in the model directory.
  Future<bool> hasExtraAssets(Directory modelDir) async {
    for (final file in tokenizerFiles) {
      if (!(await File('${modelDir.path}/$file').exists())) return false;
    }
    if (!(await File('${modelDir.path}/$embedTokensFile').exists())) {
      return false;
    }
    if (!(await File('${modelDir.path}/$tEmbedderFile').exists())) {
      return false;
    }
    return true;
  }

  /// Verifies pinned sizes/hashes for staged + derived files.
  ///
  /// Unpinned entries are skipped, so this passes vacuously until pins are
  /// populated. Throws [StateError] naming the first mismatch (missing file,
  /// size drift, or hash drift) — callers treat that as "re-download".
  Future<void> verifyFilePins(Directory modelDir) async {
    for (final MapEntry<String, int> pin in expectedSizes.entries) {
      if (pin.value <= 0) continue;
      final File file = File('${modelDir.path}/${pin.key}');
      if (!await file.exists()) {
        throw StateError('Pinned file missing: ${pin.key}');
      }
      final int actual = await file.length();
      if (actual != pin.value) {
        throw StateError(
          'Size mismatch for ${pin.key}: expected ${pin.value}, got $actual',
        );
      }
    }
    for (final MapEntry<String, String> pin in expectedSha256.entries) {
      final String want = pin.value.trim().toLowerCase();
      if (want.isEmpty) continue;
      final File file = File('${modelDir.path}/${pin.key}');
      if (!await file.exists()) {
        throw StateError('Pinned file missing: ${pin.key}');
      }
      final String actual = await sha256HexOfFile(file);
      if (actual != want) {
        throw StateError('SHA-256 mismatch for ${pin.key}');
      }
    }
  }
}

extension DiffusionModelExtensions on DiffusionModel {
  DiffusionExtraAssets get extraAssets => switch (this) {
    DiffusionModel.zImageTurbo => const DiffusionExtraAssets(
      tokenizerRepoId: 'Tongyi-MAI/Z-Image-Turbo',
      tokenizerFiles: [
        'tokenizer/vocab.json',
        'tokenizer/merges.txt',
        'tokenizer/tokenizer.json',
        'tokenizer/tokenizer_config.json',
      ],
      embedTokensRepoId: 'Tongyi-MAI/Z-Image-Turbo',
      embedTokensSource: 'text_encoder/model-00001-of-00003.safetensors',
      embedTokensFile: 'embed_tokens.safetensors',
      tEmbedderRepoId: 'Tongyi-MAI/Z-Image-Turbo',
      tEmbedderSource:
          'transformer/diffusion_pytorch_model-00001-of-00003.safetensors',
      tEmbedderFile: 't_embedder.safetensors',
    ),
    DiffusionModel.flux2Klein => const DiffusionExtraAssets(
      tokenizerRepoId: 'litert-community/FLUX.2-klein-4B-LiteRT',
      tokenizerFiles: [],
      embedTokensRepoId: '',
      embedTokensSource: '',
      embedTokensFile: 'embed_tokens.safetensors',
      tEmbedderRepoId: '',
      tEmbedderSource: '',
      tEmbedderFile: 't_embedder.safetensors',
    ),
  };

  String get capabilitySummary => 'Diffusion';

  String get sizeLabel => '$approxSizeMB MB';
}

class DiffusionModelInfo {
  const DiffusionModelInfo({
    required this.model,
    required this.fileName,
    required this.repoId,
    required this.approxSizeMB,
    required this.gated,
    required this.tags,
    required this.pipelineTag,
  });

  final DiffusionModel model;
  final String fileName;
  final String repoId;
  final int approxSizeMB;
  final bool gated;
  final List<String> tags;
  final String pipelineTag;

  String get displayName => model.displayName;

  String get author {
    final slash = repoId.indexOf('/');
    if (slash <= 0) return 'litert-community';
    return repoId.substring(0, slash);
  }
}

class DiffusionModelCatalog {
  const DiffusionModelCatalog._();

  static const recommended = <DiffusionModelInfo>[
    DiffusionModelInfo(
      model: DiffusionModel.zImageTurbo,
      fileName: 'Z-Image-Turbo-LiteRT',
      repoId: 'litert-community/Z-Image-Turbo-LiteRT',
      approxSizeMB: 9400,
      gated: false,
      tags: ['z-image-turbo', 'fast', 'diffusion'],
      pipelineTag: 'text-to-image',
    ),
    DiffusionModelInfo(
      model: DiffusionModel.flux2Klein,
      fileName: 'FLUX.2-klein-4B-LiteRT',
      repoId: 'litert-community/FLUX.2-klein-4B-LiteRT',
      approxSizeMB: 9600,
      gated: true,
      tags: ['flux', 'high-quality', 'diffusion'],
      pipelineTag: 'text-to-image',
    ),
  ];

  static DiffusionModelInfo? forModel(DiffusionModel model) {
    for (final entry in recommended) {
      if (entry.model == model) return entry;
    }
    return null;
  }

  static DiffusionModelInfo? byFileName(String fileName) {
    final lower = fileName.toLowerCase();
    for (final entry in recommended) {
      if (entry.fileName.toLowerCase() == lower) return entry;
    }
    return null;
  }

  static DiffusionModelInfo? byRepoId(String repoId) {
    final lower = repoId.toLowerCase();
    for (final entry in recommended) {
      if (entry.repoId.toLowerCase() == lower) return entry;
    }
    return null;
  }

  static String repoIdFor(DiffusionModel model) =>
      forModel(model)?.repoId ?? '';
}

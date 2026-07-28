import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/huggingface_hub_service.dart';

/// Single source of truth for Nova's recommended litert-community models.
class RecommendedLiteRtModel {
  const RecommendedLiteRtModel({
    required this.novaModel,
    required this.repoId,
    required this.fileName,
    required this.approxSizeMB,
    required this.gated,
    required this.tags,
    required this.pipelineTag,
  });

  final NovaModel novaModel;
  final String repoId;
  final String fileName;
  final int approxSizeMB;
  final bool gated;
  final List<String> tags;
  final String pipelineTag;

  String get displayName => novaModel.displayName;

  String get author {
    final slash = repoId.indexOf('/');
    if (slash <= 0) return 'litert-community';

    return repoId.substring(0, slash);
  }

  String get downloadUrl =>
      HuggingfaceHubService.resolveDownloadUrl(repoId, path: fileName);

  ModelType get modelType => novaModel.modelType;
  ModelFileType get fileType => novaModel.fileType;
  bool get hasVision => novaModel.hasVision;
  bool get hasThinking => novaModel.hasThinking;
}

/// Curated built-in catalog shared by browser, URLs, and update service.
class LiteRtModelCatalog {
  const LiteRtModelCatalog._();

  static const recommended = <RecommendedLiteRtModel>[
    RecommendedLiteRtModel(
      novaModel: NovaModel.smollm,
      repoId: 'litert-community/SmolLM-135M-Instruct',
      fileName: 'SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
      approxSizeMB: 135,
      gated: false,
      tags: ['smollm', 'fast'],
      pipelineTag: 'text-generation',
    ),
    RecommendedLiteRtModel(
      novaModel: NovaModel.fastvlm,
      repoId: 'litert-community/FastVLM-0.5B',
      fileName: 'FastVLM-0.5B.litertlm',
      approxSizeMB: 500,
      gated: false,
      tags: ['fastvlm', 'vision', 'fast'],
      pipelineTag: 'image-text-to-text',
    ),
    RecommendedLiteRtModel(
      novaModel: NovaModel.gemma3_1b,
      repoId: 'litert-community/Gemma3-1B-IT',
      fileName: 'gemma3-1b-it-int4.litertlm',
      approxSizeMB: 500,
      gated: true,
      tags: ['gemma3', 'balanced'],
      pipelineTag: 'text-generation',
    ),
    RecommendedLiteRtModel(
      novaModel: NovaModel.gemma4E2b,
      repoId: 'litert-community/gemma-4-E2B-it-litert-lm',
      fileName: 'gemma-4-E2B-it.litertlm',
      approxSizeMB: 2400,
      gated: true,
      tags: ['gemma4', 'vision', 'thinking', 'heavy'],
      pipelineTag: 'image-text-to-text',
    ),
  ];

  static RecommendedLiteRtModel? forNovaModel(NovaModel model) {
    for (final entry in recommended) {
      if (entry.novaModel == model) return entry;
    }

    return null;
  }

  static RecommendedLiteRtModel? byFileName(String fileName) {
    final lower = fileName.toLowerCase();
    for (final entry in recommended) {
      if (entry.fileName.toLowerCase() == lower) return entry;
    }

    return null;
  }

  static RecommendedLiteRtModel? byRepoId(String repoId) {
    final lower = repoId.toLowerCase();
    for (final entry in recommended) {
      if (entry.repoId.toLowerCase() == lower) return entry;
    }

    return null;
  }

  static String repoIdFor(NovaModel model) => forNovaModel(model)?.repoId ?? '';
}

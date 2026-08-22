import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/services/huggingface_hub_service.dart';

/// Curated uncensored chat models that ship LiteRT-native assets
/// (`.litertlm` / `.task`) and can run through flutter_gemma as
/// [CustomModel]s.
///
/// Every entry was verified against the HuggingFace Hub tree API before
/// being added here. [UncensoredModelEntry.expectedSha256] carries the
/// LFS blob SHA-256 observed at curation time; ModelManager.verifyModelHash
/// rejects downloads whose digest mismatches, so tampered or substituted
/// upstream assets cannot be installed.
///
/// GGUF-only repos must NOT be listed: flutter_gemma cannot execute GGUF
/// weights.
class UncensoredModelEntry {
  final String repoId;
  final String displayName;
  final String fileName;
  final int approxSizeMB;
  final bool gated;
  final List<String> tags;
  final String description;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool hasVision;
  final bool hasThinking;
  final int maxContextTokens;
  final String expectedSha256;

  const UncensoredModelEntry({
    required this.repoId,
    required this.displayName,
    required this.fileName,
    required this.approxSizeMB,
    required this.gated,
    required this.tags,
    required this.description,
    required this.modelType,
    required this.fileType,
    this.hasVision = false,
    this.hasThinking = false,
    this.maxContextTokens = 4096,
    required this.expectedSha256,
  });

  String get downloadUrl =>
      HuggingfaceHubService.resolveDownloadUrl(repoId, path: fileName);

  String get sizeLabel => '~$approxSizeMB MB';
}

class UncensoredModelCatalog {
  const UncensoredModelCatalog._();

  static const recommended = <UncensoredModelEntry>[
    UncensoredModelEntry(
      repoId: 'PeppX/gemma-4-e2b-uncensored-litertlm',
      displayName: 'Gemma 4 E2B Uncensored MAX',
      fileName: 'gemma4_uncensored_INT4_8192.litertlm',
      approxSizeMB: 2451,
      gated: false,
      tags: ['uncensored', 'gemma4', 'int4', 'on-device'],
      description:
          'Gemma 4 E2B fine-tuned to answer without refusals. INT4 '
          'quantized, 8192 token context.',
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
      hasVision: true,
      hasThinking: true,
      maxContextTokens: 8192,
      expectedSha256:
          '7c1dd5e4723e8a6d20fbb5f11f34141eb1f8e413d2049aa52211f533966d785e',
    ),
    UncensoredModelEntry(
      repoId: 'nqd145/Gemma-4-E2B-it-abliterated-litertlm',
      displayName: 'Gemma 4 E2B Abliterated',
      fileName: 'Gemma-4-E2B-it-abliterated.litertlm',
      approxSizeMB: 4830,
      gated: false,
      tags: ['abliterated', 'uncensored', 'gemma4'],
      description:
          'Abliterated Gemma 4 E2B with refusal directions removed. '
          'Large file — needs a device with ample free RAM/storage.',
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
      hasVision: true,
      hasThinking: true,
      maxContextTokens: 8192,
      expectedSha256:
          '3bb979594d6fd1a958c7f9c5dbfbdf9d1312ee3eaae009d298b6f19194392953',
    ),
  ];

  static UncensoredModelEntry? byRepoId(String repoId) {
    final lower = repoId.toLowerCase();
    for (final entry in recommended) {
      if (entry.repoId.toLowerCase() == lower) return entry;
    }

    return null;
  }

  /// Integrity pin for [fileName], consumed by ModelManager.verifyModelHash.
  static String? expectedSha256For(String fileName) {
    for (final entry in recommended) {
      if (entry.fileName == fileName) return entry.expectedSha256;
    }

    return null;
  }
}

enum DiffusionModel {
  zImageTurbo(
    'Z-Image-Turbo-LiteRT',
    'Z-Image-Turbo',
    'litert-community/Z-Image-Turbo-LiteRT',
    800,
  ),
  flux2Klein(
    'FLUX.2-klein-4B-LiteRT',
    'FLUX.2-klein-4B',
    'litert-community/FLUX.2-klein-4B-LiteRT',
    2400,
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
      approxSizeMB: 800,
      gated: false,
      tags: ['z-image-turbo', 'fast', 'diffusion'],
      pipelineTag: 'text-to-image',
    ),
    DiffusionModelInfo(
      model: DiffusionModel.flux2Klein,
      fileName: 'FLUX.2-klein-4B-LiteRT',
      repoId: 'litert-community/FLUX.2-klein-4B-LiteRT',
      approxSizeMB: 2400,
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

extension DiffusionModelExtensions on DiffusionModel {
  String get capabilitySummary => 'Diffusion';

  String get sizeLabel => '$approxSizeMB MB';
}

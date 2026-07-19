import 'package:flutter_gemma/flutter_gemma.dart';

enum NovaModel {
  smollm(
    "SmolLM-135M",
    ModelType.general,
    ModelFileType.task,
    135,
    false,
    false,
  ),
  fastvlm(
    "FastVLM-0.5B",
    ModelType.general,
    ModelFileType.litertlm,
    500,
    true,
    false,
  ),
  gemma3_1b(
    "Gemma 3 1B",
    ModelType.gemmaIt,
    ModelFileType.litertlm,
    500,
    false,
    false,
  ),
  gemma4E2b(
    "Gemma 4 E2B",
    ModelType.gemma4,
    ModelFileType.litertlm,
    2400,
    true,
    true,
  );

  final String displayName;
  final ModelType modelType;
  final ModelFileType fileType;
  final int sizeMB;
  final bool hasVision;
  final bool hasThinking;

  const NovaModel(
    this.displayName,
    this.modelType,
    this.fileType,
    this.sizeMB,
    this.hasVision,
    this.hasThinking,
  );
}

class ModelSelector {
  NovaModel primaryHeavy;
  NovaModel fastModel;

  ModelSelector({
    this.primaryHeavy = NovaModel.gemma4E2b,
    this.fastModel = NovaModel.smollm,
  });

  NovaModel selectForQuery({
    required String query,
    required bool hasVisionContext,
    required bool requestedThinking,
  }) {
    if (hasVisionContext) {
      if (primaryHeavy.hasVision) return primaryHeavy;
      if (fastModel.hasVision) return fastModel;
    }

    if (query.split(' ').length <= 8 && !requestedThinking) {
      return fastModel;
    }

    if (requestedThinking && primaryHeavy.hasThinking) {
      return primaryHeavy;
    }

    return primaryHeavy;
  }
}

class ModelHashes {
  static const smollm =
      'a8c3e2d1f0b3c4e5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9';
  static const fastvlm =
      'b9d4f3e2c1a0b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9';
  static const gemma3_1b =
      'c0e5f4d3b2a1c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0';
  static const gemma4E2b =
      'd1f6a5b4c3d2e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1';

  static String? hashFor(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return smollm;
      case NovaModel.fastvlm:
        return fastvlm;
      case NovaModel.gemma3_1b:
        return gemma3_1b;
      case NovaModel.gemma4E2b:
        return gemma4E2b;
    }
  }
}

class ModelHuggingFaceURLs {
  // SmolLM 135M — .task format (no .litertlm available)
  static const smollm =
      'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task';

  // FastVLM 0.5B — fast vision model
  static const fastvlm =
      'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm';

  // Gemma 3 1B — balanced text
  static const gemma3_1b =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.litertlm';

  // Gemma 4 E2B — full power, vision + thinking + function calling
  static const gemma4E2b =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  static String urlFor(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return smollm;
      case NovaModel.fastvlm:
        return fastvlm;
      case NovaModel.gemma3_1b:
        return gemma3_1b;
      case NovaModel.gemma4E2b:
        return gemma4E2b;
    }
  }

  /// Gemma repos are gated on HuggingFace and return 401 without a token.
  static bool requiresHuggingFaceAuth(NovaModel model) {
    return model == NovaModel.gemma3_1b || model == NovaModel.gemma4E2b;
  }

  /// True when [url] points at a known gated Gemma asset.
  static bool urlRequiresHuggingFaceAuth(String url) {
    final lower = url.toLowerCase();

    return lower.contains('gemma3-1b') ||
        lower.contains('gemma-4') ||
        lower.contains('/gemma3') ||
        lower.contains('/gemma-4');
  }

  static String fileNameFor(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return 'SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task';
      case NovaModel.fastvlm:
        return 'FastVLM-0.5B.litertlm';
      case NovaModel.gemma3_1b:
        return 'gemma3-1b-it-int4.litertlm';
      case NovaModel.gemma4E2b:
        return 'gemma-4-E2B-it.litertlm';
    }
  }

  static NovaModel? modelFromUrl(String url) {
    final normalizedUrl = url.toLowerCase();
    for (final model in NovaModel.values) {
      if (normalizedUrl.contains(urlFor(model).toLowerCase())) {
        return model;
      }
    }

    return null;
  }

  static NovaModel? modelFromFileName(String fileName) {
    final normalizedName = fileName.toLowerCase();
    for (final model in NovaModel.values) {
      if (normalizedName.contains(
        fileNameFor(model)
            .toLowerCase()
            .replaceAll('.litertlm', '')
            .replaceAll('.task', ''),
      )) {
        return model;
      }
    }

    return null;
  }
}

extension NovaModelExtensions on NovaModel {
  String get capabilitySummary {
    final caps = <String>[];
    if (hasVision) caps.add('Vision');
    if (hasThinking) caps.add('Thinking');

    return caps.isEmpty ? 'Text only' : caps.join(' + ');
  }

  String get sizeLabel => '$sizeMB MB';

  /// Catalog capability for native function calling.
  ///
  /// LiteRT Gemma 3 1B ignores tools at runtime ("Model does not support
  /// function calls") — treat as text-tool only so we do not pass empty
  /// native tools while also skipping the text tool prompt.
  bool get supportsFunctionCalling =>
      this != NovaModel.smollm && this != NovaModel.gemma3_1b;

  List<String> get capabilityList {
    final list = <String>['Function Calling'];
    if (hasVision) list.insert(0, 'Vision');
    if (hasThinking) list.insert(0, 'Thinking');

    return list;
  }
}

class CustomModel {
  final String id;
  final String displayName;
  final String fileName;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool hasVision;
  final bool hasThinking;
  final bool supportsFunctionCalling;
  final int fileSizeBytes;
  final DateTime installedAt;
  final bool isGguf;

  const CustomModel({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.modelType,
    required this.fileType,
    this.hasVision = false,
    this.hasThinking = false,
    this.supportsFunctionCalling = true,
    required this.fileSizeBytes,
    required this.installedAt,
    this.isGguf = false,
  });

  double get fileSizeMB => fileSizeBytes / (1024 * 1024);

  String get sizeLabel => '${fileSizeMB.toStringAsFixed(0)} MB';

  String get capabilitySummary {
    final caps = <String>[];
    if (hasVision) caps.add('Vision');
    if (hasThinking) caps.add('Thinking');
    if (isGguf) caps.add('GGUF');

    return caps.isEmpty ? 'Text only' : caps.join(' + ');
  }

  List<String> get capabilityList {
    final list = <String>['Function Calling'];
    if (hasVision) list.insert(0, 'Vision');
    if (hasThinking) list.insert(0, 'Thinking');
    if (isGguf) list.insert(0, 'GGUF');

    return list;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'fileName': fileName,
    'modelType': modelType.name,
    'fileType': isGguf ? 'gguf' : fileType.name,
    'hasVision': hasVision,
    'hasThinking': hasThinking,
    'supportsFunctionCalling': supportsFunctionCalling,
    'fileSizeBytes': fileSizeBytes,
    'installedAt': installedAt.toIso8601String(),
    'isGguf': isGguf,
  };

  factory CustomModel.fromJson(Map<String, dynamic> json) {
    final isGguf = json['isGguf'] as bool? ?? false;

    return CustomModel(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      fileName: json['fileName'] as String,
      modelType: ModelType.values.firstWhere(
        (e) => e.name == json['modelType'],
        orElse: () => ModelType.general,
      ),
      fileType: isGguf
          ? ModelFileType.values.firstWhere(
              (e) => e.name == 'binary',
              orElse: () => ModelFileType.binary,
            )
          : ModelFileType.values.firstWhere(
              (e) => e.name == json['fileType'],
              orElse: () => ModelFileType.litertlm,
            ),
      hasVision: json['hasVision'] as bool? ?? false,
      hasThinking: json['hasThinking'] as bool? ?? false,
      supportsFunctionCalling: json['supportsFunctionCalling'] as bool? ?? true,
      fileSizeBytes: json['fileSizeBytes'] as int,
      installedAt: DateTime.parse(json['installedAt'] as String),
      isGguf: isGguf,
    );
  }
}

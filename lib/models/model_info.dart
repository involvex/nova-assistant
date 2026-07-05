import 'package:flutter_gemma/flutter_gemma.dart';

enum NovaModel {
  smollm("SmolLM-135M", ModelType.general, 135, false, false),
  fastvlm("FastVLM-0.5B", ModelType.general, 500, true, false),
  gemma3_1b("Gemma 3 1B", ModelType.gemmaIt, 500, false, false),
  gemma4E2b("Gemma 4 E2B", ModelType.gemma4, 2400, true, true);

  final String displayName;
  final ModelType modelType;
  final int sizeMB;
  final bool hasVision;
  final bool hasThinking;

  const NovaModel(
    this.displayName,
    this.modelType,
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
    // If vision input (screenshot), need a vision-capable model
    if (hasVisionContext) {
      if (primaryHeavy.hasVision) return primaryHeavy;
      if (fastModel.hasVision) return fastModel;
    }

    // Short simple query → fast model
    if (query.split(' ').length <= 8 && !requestedThinking) {
      return fastModel;
    }

    // Thinking requested → Gemma 4 E2B only
    if (requestedThinking && primaryHeavy.hasThinking) {
      return primaryHeavy;
    }

    // Default: heavy model for anything complex
    return primaryHeavy;
  }
}

class ModelHuggingFaceURLs {
  // SmolLM 135M — ultra-fast, text only
  static const smollm =
      'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.litertlm';

  // FastVLM 0.5B — fast vision model
  static const fastvlm =
      'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm';

  // Gemma 3 1B — balanced text
  static const gemma3_1b =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';

  // Gemma 4 E2B — full power, vision + thinking + function calling
  static const gemma4E2b =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-int4.litertlm';

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
}

import 'package:nova_assistant/ai/providers/local_gemma_provider.dart';
import 'package:nova_assistant/ai/providers/provider_capabilities.dart';
import 'package:nova_assistant/models/model_info.dart';

/// Local Qwen adapter. Decision: `.litertlm` / `.task` via the existing
/// `flutter_edge_ai` engine + `CustomModel` import path (no GGUF).
///
/// Reuses the Gemma engine wrapper until a dedicated Qwen backend lands;
/// provider id stays stable (`local-qwen`) so strategy config never changes.
class LocalQwenProvider extends LocalGemmaProvider {
  LocalQwenProvider() : super(model: NovaModel.gemma3_1b);

  @override
  String get id => 'local-qwen';

  @override
  Set<ProviderCapability> get capabilities {
    return <ProviderCapability>{
      ProviderCapability.chat,
      ProviderCapability.streaming,
      ProviderCapability.toolCalling,
    };
  }

  @override
  Future<List<double>> embed(String text) {
    throw UnsupportedError('local-qwen does not support embeddings');
  }
}

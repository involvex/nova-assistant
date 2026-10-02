import 'package:nova_assistant/ai/router/intent.dart';
import 'package:nova_assistant/core/config/provider_config.dart';

/// Maps an [Intent] to a provider id via `providers.yaml`.
/// Pure function of config — no I/O, fully testable.
class ProviderStrategy {
  const ProviderStrategy(this.config);

  final ProviderConfig config;

  String providerIdFor(Intent intent) {
    return config.providerFor(intent.useCase);
  }

  String providerIdForUseCase(String useCase) {
    return config.providerFor(useCase);
  }
}

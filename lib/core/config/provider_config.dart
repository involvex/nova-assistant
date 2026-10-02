import 'package:flutter/services.dart';

/// Loads `assets/config/providers.yaml` (build asset, read-only).
///
/// Minimal line parser on purpose: no yaml dependency. Supports:
/// ```yaml
/// simple:
///   provider: local-gemma
/// coding:
///   provider: openrouter
/// ```
class ProviderConfig {
  const ProviderConfig(this.byUseCase);

  final Map<String, String> byUseCase;

  static const String assetPath = 'assets/config/providers.yaml';

  static const List<String> knownUseCases = <String>[
    'simple',
    'coding',
    'vision',
    'automation',
    'fallback',
  ];

  String providerFor(String useCase) {
    return byUseCase[useCase] ?? byUseCase['fallback'] ?? 'local-gemma';
  }

  static Future<ProviderConfig> load({String path = assetPath}) async {
    final String raw = await rootBundle.loadString(path);

    return parse(raw);
  }

  static ProviderConfig parse(String raw) {
    final Map<String, String> result = <String, String>{};
    String? currentSection;
    for (final String line in raw.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        final int colon = trimmed.indexOf(':');
        if (colon > 0) {
          currentSection = trimmed.substring(0, colon).trim();
        }
        continue;
      }
      if (currentSection != null && trimmed.startsWith('provider:')) {
        final String value = trimmed
            .substring('provider:'.length)
            .trim()
            .replaceAll('"', '')
            .replaceAll("'", '');
        if (value.isNotEmpty) {
          result[currentSection] = value;
        }
      }
    }

    return ProviderConfig(Map<String, String>.unmodifiable(result));
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';
import 'package:nova_assistant/models/diffusion_model_info.dart';

class ImageGenerationService {
  static const _channel = MethodChannel('dev.nova.assistant/image_gen');

  static ImageGenerationService? _instance;
  static ImageGenerationService get instance =>
      _instance ??= ImageGenerationService._();

  ImageGenerationService._();

  final _progressController = StreamController<GenProgress>.broadcast();
  Stream<GenProgress> get progressStream => _progressController.stream;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  Future<Uint8List?> generateImage(
    String prompt, {
    ImageSize size = ImageSize.size512,
    int? seed,
    DiffusionModel? model,
  }) async {
    if (_isGenerating) {
      debugPrint('ImageGenerationService: already generating');
      return null;
    }

    if (prompt.trim().isEmpty) {
      debugPrint('ImageGenerationService: empty prompt');
      return null;
    }

    if (!await AdultModePolicy.isEnabled()) {
      final safe = AdultModePolicy.isPromptSafe(prompt);
      if (!safe) {
        debugPrint(
          'ImageGenerationService: prompt blocked by adult mode policy',
        );
        return null;
      }
    }

    _isGenerating = true;

    try {
      _progressController.add(
        GenProgress(stage: 'start', percent: 0, message: 'Starting...'),
      );

      final result = await _channel.invokeMethod<Uint8List>(
        'generateImage',
        <String, dynamic>{
          'prompt': prompt,
          'size': size.pixels,
          'seed': seed,
          'model': model?.name,
        },
      );

      return result;
    } on PlatformException catch (e) {
      debugPrint('ImageGenerationService: PlatformException — ${e.message}');
      return null;
    } on MissingPluginException {
      debugPrint('ImageGenerationService: channel not available');
      return null;
    } catch (e) {
      debugPrint('ImageGenerationService: failed — $e');
      return null;
    } finally {
      _isGenerating = false;
      _progressController.add(
        GenProgress(stage: 'done', percent: 100, message: 'Done'),
      );
    }
  }

  Future<bool> isModelInstalled([DiffusionModel? model]) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isModelInstalled',
        <String, dynamic>{'model': model?.name},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<DiffusionModel>> getInstalledModels() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledModels',
      );
      if (result == null) return <DiffusionModel>[];

      return result
          .whereType<String>()
          .map(
            (name) => DiffusionModel.values.firstWhere(
              (m) => m.name == name,
              orElse: () => DiffusionModel.zImageTurbo,
            ),
          )
          .toList();
    } catch (_) {
      return <DiffusionModel>[];
    }
  }

  void dispose() {
    _progressController.close();
  }
}

class GenProgress {
  final String stage;
  final int percent;
  final String message;

  const GenProgress({
    required this.stage,
    required this.percent,
    required this.message,
  });
}

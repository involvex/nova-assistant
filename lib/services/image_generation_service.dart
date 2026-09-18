import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';
import 'package:nova_assistant/models/diffusion_model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';

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

  /// Channel ID must be the Hub folder name (e.g. `Z-Image-Turbo-LiteRT`),
  /// not the Dart enum name (`zImageTurbo`).
  String _channelModelId(DiffusionModel model) => model.fileName;

  DiffusionModel? _matchDiffusionModel(String id) {
    for (final model in DiffusionModel.values) {
      if (model.fileName == id ||
          model.name == id ||
          id.contains(model.fileName) ||
          model.fileName.contains(id)) {
        return model;
      }
    }

    return null;
  }

  Future<DiffusionModel?> resolveInstalledModel([
    DiffusionModel? preferred,
  ]) async {
    if (preferred != null) {
      final ok = await isModelInstalled(preferred);
      if (ok) return preferred;
    }

    for (final model in DiffusionModel.values) {
      if (ModelManager.instance.isDiffusionModelInstalled(model)) {
        final path = await ModelManager.instance.findDiffusionModelPath(model);
        if (path != null) return model;
      }
    }

    final fromNative = await getInstalledModels();
    if (fromNative.isNotEmpty) return fromNative.first;

    for (final model in DiffusionModel.values) {
      if (await isModelInstalled(model)) return model;
    }

    return null;
  }

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

    final resolved = await resolveInstalledModel(model);
    if (resolved == null) {
      debugPrint('ImageGenerationService: no diffusion model installed');
      return null;
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
          'model': _channelModelId(resolved),
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
    if (model != null) {
      if (ModelManager.instance.isDiffusionModelInstalled(model)) {
        final path = await ModelManager.instance.findDiffusionModelPath(model);
        if (path != null) return true;
      }
    } else {
      for (final m in DiffusionModel.values) {
        if (ModelManager.instance.isDiffusionModelInstalled(m)) {
          final path = await ModelManager.instance.findDiffusionModelPath(m);
          if (path != null) return true;
        }
      }
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'isModelInstalled',
        <String, dynamic>{
          'model': model == null ? null : _channelModelId(model),
        },
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

      final models = <DiffusionModel>[];
      for (final raw in result.whereType<String>()) {
        final match = _matchDiffusionModel(raw);
        if (match != null && !models.contains(match)) {
          models.add(match);
        }
      }

      return models;
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';
import 'package:nova_assistant/models/diffusion_model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';

/// Optional hook to free LLM RAM before diffusion (set from app init).
typedef ImageGenMemoryHook = Future<void> Function();

class ImageGenerationService {
  static const _channel = MethodChannel('dev.nova.assistant/image_gen');

  static ImageGenerationService? _instance;
  static ImageGenerationService get instance =>
      _instance ??= ImageGenerationService._();

  ImageGenerationService._();

  /// Avoids a circular import with [ModelOrchestrator].
  static ImageGenMemoryHook? beforeGenerateHook;

  final _progressController = StreamController<GenProgress>.broadcast();
  Stream<GenProgress> get progressStream => _progressController.stream;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  /// Last native / policy error from [generateImage] (for UI).
  String? lastError;

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

  Future<void> _freeLlmMemory() async {
    final hook = beforeGenerateHook;
    if (hook == null) return;
    try {
      _progressController.add(
        const GenProgress(
          stage: 'free_llm',
          percent: 2,
          message: 'Freeing chat model memory...',
        ),
      );
      await hook();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      debugPrint('ImageGenerationService: LLM release failed: $e');
    }
  }

  Future<Uint8List?> generateImage(
    String prompt, {
    ImageSize size = ImageSize.size256,
    int? seed,
    DiffusionModel? model,
  }) async {
    lastError = null;
    if (_isGenerating) {
      lastError = 'An image is already being generated';
      debugPrint('ImageGenerationService: already generating');
      return null;
    }

    if (prompt.trim().isEmpty) {
      lastError = 'Prompt is empty';
      debugPrint('ImageGenerationService: empty prompt');
      return null;
    }

    if (!await AdultModePolicy.isEnabled()) {
      final safe = AdultModePolicy.isPromptSafe(prompt);
      if (!safe) {
        lastError = 'Prompt blocked by adult mode policy';
        debugPrint(
          'ImageGenerationService: prompt blocked by adult mode policy',
        );
        return null;
      }
    }

    final resolved = await resolveInstalledModel(model);
    if (resolved == null) {
      lastError = 'No diffusion model installed';
      debugPrint('ImageGenerationService: no diffusion model installed');
      return null;
    }

    // Fail before unloading Gemma — Z-Image/FLUX installs are download-only
    // until the LiteRT host loop ships (avoids "Skipped N frames" jank).
    if (!resolved.inferenceReady) {
      lastError = resolved.runnerNotReadyMessage;
      debugPrint('ImageGenerationService: ${resolved.runnerNotReadyMessage}');
      return null;
    }

    _isGenerating = true;

    try {
      _progressController.add(
        const GenProgress(stage: 'start', percent: 0, message: 'Starting...'),
      );

      await _freeLlmMemory();

      // Only resolve the documents path when prefs know the install — avoids
      // hanging on path_provider in tests / before the plugin is ready.
      final modelPath =
          ModelManager.instance.isDiffusionModelInstalled(resolved)
          ? await ModelManager.instance.findDiffusionModelPath(resolved)
          : null;
      final result = await _channel.invokeMethod<Uint8List>(
        'generateImage',
        <String, dynamic>{
          'prompt': prompt,
          'size': size.pixels,
          'seed': seed,
          'model': _channelModelId(resolved),
          'modelDir': ?modelPath,
        },
      );

      return result;
    } on PlatformException catch (e) {
      lastError = e.message ?? 'Image generation failed';
      debugPrint('ImageGenerationService: PlatformException — ${e.message}');
      return null;
    } on MissingPluginException {
      lastError = 'Image generation is not available on this platform';
      debugPrint('ImageGenerationService: channel not available');
      return null;
    } catch (e) {
      lastError = e.toString();
      debugPrint('ImageGenerationService: failed — $e');
      return null;
    } finally {
      _isGenerating = false;
      _progressController.add(
        const GenProgress(stage: 'done', percent: 100, message: 'Done'),
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
      final modelPath =
          model != null &&
              ModelManager.instance.isDiffusionModelInstalled(model)
          ? await ModelManager.instance.findDiffusionModelPath(model)
          : null;
      final result = await _channel.invokeMethod<bool>(
        'isModelInstalled',
        <String, dynamic>{
          'model': model == null ? null : _channelModelId(model),
          'modelDir': ?modelPath,
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

  /// Test-only: clear in-flight generation flag on the singleton.
  @visibleForTesting
  void resetForTest() {
    _isGenerating = false;
    lastError = null;
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

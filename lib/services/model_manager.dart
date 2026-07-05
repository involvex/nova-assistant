import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class InstalledModel {
  final String id;
  final String fileName;
  final ModelType modelType;
  final DateTime installedAt;
  final int fileSizeBytes;

  InstalledModel({
    required this.id,
    required this.fileName,
    required this.modelType,
    required this.installedAt,
    required this.fileSizeBytes,
  });

  double get fileSizeMB => fileSizeBytes / (1024 * 1024);

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'modelType': modelType.name,
    'installedAt': installedAt.toIso8601String(),
    'fileSizeBytes': fileSizeBytes,
  };

  factory InstalledModel.fromJson(Map<String, dynamic> json) => InstalledModel(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    modelType: ModelType.values.firstWhere(
      (e) => e.name == json['modelType'],
      orElse: () => ModelType.general,
    ),
    installedAt: DateTime.parse(json['installedAt'] as String),
    fileSizeBytes: json['fileSizeBytes'] as int,
  );
}

class ModelManager {
  static ModelManager? _instance;
  static ModelManager get instance => _instance ??= ModelManager._();
  ModelManager._();

  static const _prefsKey = 'installed_models';
  final List<InstalledModel> _installedModels = [];

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  List<InstalledModel> get installedModels =>
      List.unmodifiable(_installedModels);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_prefsKey);
    if (jsonList != null) {
      _installedModels.clear();
      for (final json in jsonList) {
        try {
          final map = Map<String, dynamic>.from(
            Map<String, dynamic>.from(json as Map<dynamic, dynamic>),
          );
          _installedModels.add(InstalledModel.fromJson(map));
        } catch (_) {
          // Skip corrupted entries
        }
      }
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _installedModels
        .map((m) => m.toJson().toString())
        .toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  Future<InstalledModel?> installFromNetwork({
    required String url,
    required ModelType modelType,
    void Function(int progress)? onProgress,
  }) async {
    try {
      _statusController.add('Downloading model...');
      final builder = FlutterGemma.installModel(
        modelType: modelType,
      ).fromNetwork(url);
      if (onProgress != null) {
        builder.withProgress(onProgress);
      }
      final result = await builder.install();
      final spec = result.spec;

      final file = await _findInstalledFile(spec.name);
      final model = InstalledModel(
        id: spec.name,
        fileName: spec.name,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: file != null ? await file.length() : 0,
      );

      _installedModels.add(model);
      await _saveToPrefs();
      _statusController.add('Model installed: ${spec.name}');
      return model;
    } catch (e) {
      _statusController.add('Install failed: $e');
      debugPrint('ModelManager: installFromNetwork failed: $e');
      return null;
    }
  }

  Future<InstalledModel?> installFromFile({
    required String filePath,
    required ModelType modelType,
    void Function(int progress)? onProgress,
  }) async {
    try {
      _statusController.add('Installing model from file...');
      final builder = FlutterGemma.installModel(
        modelType: modelType,
      ).fromFile(filePath);
      if (onProgress != null) {
        builder.withProgress(onProgress);
      }
      final result = await builder.install();
      final spec = result.spec;

      final file = File(filePath);
      final model = InstalledModel(
        id: spec.name,
        fileName: spec.name,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: await file.length(),
      );

      _installedModels.add(model);
      await _saveToPrefs();
      _statusController.add('Model installed: ${spec.name}');
      return model;
    } catch (e) {
      _statusController.add('Install failed: $e');
      debugPrint('ModelManager: installFromFile failed: $e');
      return null;
    }
  }

  Future<bool> uninstallModel(String modelId) async {
    try {
      await FlutterGemma.uninstallModel(modelId);
      _installedModels.removeWhere((m) => m.id == modelId);
      await _saveToPrefs();
      _statusController.add('Model removed: $modelId');
      return true;
    } catch (e) {
      debugPrint('ModelManager: uninstallModel failed: $e');
      return false;
    }
  }

  Future<void> setActiveModel(String modelId) async {
    final model = _installedModels.where((m) => m.id == modelId).firstOrNull;
    if (model == null) {
      _statusController.add('Model not found: $modelId');
      return;
    }
    // The model is set as active during install, but we can re-trigger it
    _statusController.add('Active model: ${model.fileName}');
  }

  bool isModelInstalled(String fileName) {
    return _installedModels.any((m) => m.fileName == fileName);
  }

  Future<File?> _findInstalledFile(String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$name');
      if (await file.exists()) return file;
      // Check subdirectories
      final modelsDir = Directory('${dir.path}/models');
      if (await modelsDir.exists()) {
        await for (final entity in modelsDir.list()) {
          if (entity is File && entity.path.contains(name)) {
            return entity;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

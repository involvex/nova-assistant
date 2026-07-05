import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
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
          final map = jsonDecode(json) as Map<String, dynamic>;
          _installedModels.add(InstalledModel.fromJson(map));
        } catch (_) {}
      }
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _installedModels
        .map((m) => jsonEncode(m.toJson()))
        .toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  Future<InstalledModel?> installFromNetwork({
    required String url,
    required ModelType modelType,
    required ModelFileType fileType,
    void Function(int progress)? onProgress,
  }) async {
    try {
      _statusController.add('Preparing download...');

      final uri = Uri.parse(url);
      final fileName = p.basename(uri.path);

      // ALWAYS go through FlutterGemma's install pipeline.
      // install() is idempotent — if the model is already on disk it skips
      // download but STILL calls setActiveModel(spec) with the correct
      // fileType, which is critical for engine routing (.litertlm →
      // LiteRtLmEngine, .task → MediaPipeEngine).
      _statusController.add('Installing model...');
      final builder = FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromNetwork(url);
      if (onProgress != null) {
        builder.withProgress(onProgress);
      }
      _statusController.add('Starting download...');
      await builder.install();

      // Find the installed file
      final dir = await getApplicationDocumentsDirectory();
      final spec = await _findInstalledSpec(fileName, modelType);
      final specName = spec?['name'] as String? ?? fileName;

      final model = InstalledModel(
        id: specName,
        fileName: specName,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: await _getFileSize(dir.path, fileName),
      );

      // Dedup: remove any existing entry with the same id before adding
      _installedModels.removeWhere((m) => m.id == specName);
      _installedModels.add(model);
      await _saveToPrefs();
      _statusController.add('Model installed: ${model.fileName}');
      return model;
    } catch (e) {
      _statusController.add('Install failed: $e');
      debugPrint('ModelManager: installFromNetwork failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _findInstalledSpec(
    String fileName,
    ModelType modelType,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Check direct path
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        return {'name': fileName};
      }
      // Check models subdirectory
      final modelsDir = Directory('${dir.path}/models');
      if (await modelsDir.exists()) {
        await for (final entity in modelsDir.list()) {
          if (entity is File &&
              entity.path.contains(
                fileName.replaceAll('.litertlm', '').replaceAll('.task', ''),
              )) {
            return {'name': p.basename(entity.path)};
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<int> _getFileSize(String dirPath, String fileName) async {
    try {
      final file = File('$dirPath/$fileName');
      if (await file.exists()) return await file.length();
      final modelsDir = Directory('$dirPath/models');
      if (await modelsDir.exists()) {
        await for (final entity in modelsDir.list()) {
          if (entity is File && entity.path.contains(fileName)) {
            return await entity.length();
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<InstalledModel?> installFromFile({
    required String filePath,
    required ModelType modelType,
    required ModelFileType fileType,
    void Function(int progress)? onProgress,
  }) async {
    try {
      _statusController.add('Installing model from file...');

      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        _statusController.add('File not found: $filePath');
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = p.basename(filePath);
      final tempFile = File('${tempDir.path}/$fileName');

      _statusController.add('Copying model file...');
      await sourceFile.copy(tempFile.path);

      final builder = FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromFile(tempFile.path);
      if (onProgress != null) {
        builder.withProgress(onProgress);
      }
      final result = await builder.install();
      final spec = result.spec;

      try {
        await tempFile.delete();
      } catch (_) {}

      final model = InstalledModel(
        id: spec.name,
        fileName: spec.name,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: await sourceFile.length(),
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

  bool isModelInstalled(String fileName) {
    return _installedModels.any((m) => m.fileName == fileName);
  }
}

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
      final uri = Uri.parse(url);
      final fileName = p.basename(uri.path);

      // Check if already in our tracked list — skip download
      final existing = _installedModels.where((m) => m.fileName == fileName);
      if (existing.isNotEmpty) {
        _statusController.add('Model already installed: $fileName');
        return existing.first;
      }

      // Check if file exists on disk but not in prefs (e.g. after prefs corruption)
      final dir = await getApplicationDocumentsDirectory();
      final fileOnDisk = File('${dir.path}/$fileName');
      final modelsDir = Directory('${dir.path}/models');
      bool foundOnDisk = await fileOnDisk.exists();
      if (!foundOnDisk && await modelsDir.exists()) {
        await for (final entity in modelsDir.list()) {
          if (entity is File &&
              entity.path.contains(
                fileName.replaceAll('.litertlm', '').replaceAll('.task', ''),
              )) {
            foundOnDisk = true;
            break;
          }
        }
      }

      if (foundOnDisk) {
        // File exists on disk — find actual spec name and track it
        final spec = await _findInstalledSpec(fileName, modelType);
        final actualName = spec?['name'] as String? ?? fileName;
        final model = InstalledModel(
          id: actualName,
          fileName: actualName,
          modelType: modelType,
          installedAt: DateTime.now(),
          fileSizeBytes: await _getFileSize(dir.path, fileName),
        );
        _installedModels.removeWhere((m) => m.id == actualName);
        _installedModels.add(model);
        await _saveToPrefs();
        _statusController.add('Model found on disk: $actualName');
        return model;
      }

      // Not installed — download it
      _statusController.add('Downloading $fileName...');
      final builder = FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromNetwork(url);
      if (onProgress != null) {
        builder.withProgress(onProgress);
      }
      await builder.install();

      final spec = await _findInstalledSpec(fileName, modelType);
      final specName = spec?['name'] as String? ?? fileName;

      final model = InstalledModel(
        id: specName,
        fileName: specName,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: await _getFileSize(dir.path, fileName),
      );

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

      final fileName = p.basename(filePath);
      final docsDir = await getApplicationDocumentsDirectory();
      final targetPath = '${docsDir.path}/$fileName';

      // Copy to documents directory (flutter_gemma needs permanent access)
      if (!await File(targetPath).exists()) {
        _statusController.add('Copying model file to app storage...');
        await sourceFile.copy(targetPath);
      }

      final builder = FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromFile(targetPath);
      if (onProgress != null) {
        builder.withProgress(onProgress);
      }
      final result = await builder.install();
      final spec = result.spec;

      final model = InstalledModel(
        id: spec.name,
        fileName: spec.name,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: await sourceFile.length(),
      );

      _installedModels.removeWhere((m) => m.id == spec.name);
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

  Future<bool> isInstalledOnDisk(String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) return true;
      final modelsDir = Directory('${dir.path}/models');
      if (await modelsDir.exists()) {
        await for (final entity in modelsDir.list()) {
          if (entity is File &&
              entity.path.contains(
                fileName.replaceAll('.litertlm', '').replaceAll('.task', ''),
              )) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Register a model already on disk (no download). Used by prefetch to
  /// register existing files without triggering network requests.
  Future<void> registerDiskModel({
    required String filePath,
    required String fileName,
    required ModelType modelType,
    required ModelFileType fileType,
    required int fileSizeBytes,
  }) async {
    final existing = _installedModels.where((m) => m.fileName == fileName);
    if (existing.isNotEmpty) return;

    try {
      await FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromFile(filePath).install();

      final model = InstalledModel(
        id: fileName,
        fileName: fileName,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: fileSizeBytes,
      );
      _installedModels.removeWhere((m) => m.id == fileName);
      _installedModels.add(model);
      await _saveToPrefs();
      _statusController.add('Registered: $fileName');
    } catch (e) {
      debugPrint('registerDiskModel failed: $e — trying fuzzy match');
      // Fallback: try to find the file in models subdirectory with fuzzy match
      try {
        final dir = await getApplicationDocumentsDirectory();
        final modelsDir = Directory('${dir.path}/models');
        if (await modelsDir.exists()) {
          await for (final entity in modelsDir.list()) {
            if (entity is File &&
                p
                    .basename(entity.path)
                    .contains(
                      fileName
                          .replaceAll('.litertlm', '')
                          .replaceAll('.task', ''),
                    )) {
              try {
                await FlutterGemma.installModel(
                  modelType: modelType,
                  fileType: fileType,
                ).fromFile(entity.path).install();
                final actualName = p.basename(entity.path);
                final m = InstalledModel(
                  id: actualName,
                  fileName: actualName,
                  modelType: modelType,
                  installedAt: DateTime.now(),
                  fileSizeBytes: await entity.length(),
                );
                _installedModels.removeWhere((x) => x.id == actualName);
                _installedModels.add(m);
                await _saveToPrefs();
                _statusController.add('Registered (fuzzy): $actualName');
              } catch (_) {}
              break;
            }
          }
        }
      } catch (_) {}
    }
  }
}

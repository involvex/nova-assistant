import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:nova_assistant/models/model_info.dart';

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
        // Prefer canonical name over spec name for consistency
        final canonicalName =
            _findCanonicalName(actualName, modelType) ?? actualName;
        final model = InstalledModel(
          id: canonicalName,
          fileName: canonicalName,
          modelType: modelType,
          installedAt: DateTime.now(),
          fileSizeBytes: await _getFileSize(dir.path, fileName),
        );
        // Clean up any duplicate entries (by canonical name, spec name, or URL name)
        _installedModels.removeWhere(
          (m) =>
              m.fileName == canonicalName ||
              m.fileName == actualName ||
              m.fileName == fileName,
        );
        _installedModels.add(model);
        await _saveToPrefs();
        _statusController.add('Model found on disk: $canonicalName');
        return model;
      }

      // Not installed — download it ourselves (not via flutter_gemma's
      // fromNetwork, which stores in its internal storage invisible to
      // isInstalledOnDisk). Then delegate to installFromFile which copies
      // to the docs directory where disk checks look.
      _statusController.add('Downloading $fileName...');
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/nova_download_${DateTime.now().millisecondsSinceEpoch}$fileName',
      );

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();

        if (response.statusCode != 200) {
          _statusController.add('Download failed: HTTP ${response.statusCode}');
          return null;
        }

        final totalBytes = response.contentLength;
        var receivedBytes = 0;
        final sink = tempFile.openWrite();

        await for (final chunk in response.asBroadcastStream()) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (onProgress != null && totalBytes > 0) {
            onProgress((receivedBytes * 100 ~/ totalBytes));
          }
        }
        await sink.close();
      } finally {
        client.close();
      }

      // Delegate to installFromFile — copies to docs dir, registers with
      // flutter_gemma, and renames to canonical filename.
      final installed = await installFromFile(
        filePath: tempFile.path,
        modelType: modelType,
        fileType: fileType,
        onProgress: onProgress,
      );

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      if (installed != null) {
        _statusController.add('Model installed: ${installed.fileName}');
      }
      return installed;
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
      final ext = p.extension(fileName).toLowerCase();

      // Validate file extension — only .litertlm and .task are supported.
      // .gguf/.bin/.tflite files will crash the native engine.
      if (ext != '.litertlm' && ext != '.task') {
        _statusController.add(
          'Unsupported format: $ext — only .litertlm and .task are supported',
        );
        return null;
      }

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

      // Use the canonical filename from ModelHuggingFaceURLs instead of
      // spec.name to stay consistent with all other checks in the codebase.
      final canonicalName =
          _findCanonicalName(spec.name, modelType) ?? fileName;

      // Rename file to canonical name so isInstalledOnDisk() and
      // _findModelPath() can find it after app restart.
      final canonicalPath = '${docsDir.path}/$canonicalName';
      if (targetPath != canonicalPath) {
        final canonicalFile = File(canonicalPath);
        if (!await canonicalFile.exists()) {
          await File(targetPath).rename(canonicalPath);
        } else {
          // Canonical name already exists — clean up the temp copy
          try {
            await File(targetPath).delete();
          } catch (_) {}
        }
      }

      final model = InstalledModel(
        id: canonicalName,
        fileName: canonicalName,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: await File(canonicalPath).length(),
      );

      // Remove any entries matching this model (by canonical name, spec name,
      // or source filename) to prevent duplicates in prefs.
      _installedModels.removeWhere(
        (m) =>
            m.fileName == canonicalName ||
            m.fileName == spec.name ||
            m.fileName == fileName,
      );
      _installedModels.add(model);
      await _saveToPrefs();
      _statusController.add('Model installed: $canonicalName');
      return model;
    } catch (e) {
      _statusController.add('Install failed: $e');
      debugPrint('ModelManager: installFromFile failed: $e');
      return null;
    }
  }

  /// Find the canonical filename for a model given its flutter_gemma spec name
  /// and model type. Returns null if no match is found.
  String? _findCanonicalName(String specName, ModelType modelType) {
    for (final model in NovaModel.values) {
      if (model.modelType == modelType) {
        final canonical = ModelHuggingFaceURLs.fileNameFor(model);
        // Match by comparing normalized names (strip extensions and compare)
        final normalizedSpec = specName
            .replaceAll('.litertlm', '')
            .replaceAll('.task', '')
            .toLowerCase();
        final normalizedCanonical = canonical
            .replaceAll('.litertlm', '')
            .replaceAll('.task', '')
            .toLowerCase();
        if (normalizedSpec == normalizedCanonical ||
            normalizedSpec.contains(normalizedCanonical) ||
            normalizedCanonical.contains(normalizedSpec)) {
          return canonical;
        }
      }
    }
    return null;
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

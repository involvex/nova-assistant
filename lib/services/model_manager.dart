import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
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
  static const _hfTokenKey = 'hf_token';
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
    final jsonList =
        _installedModels.map((m) => jsonEncode(m.toJson())).toList();
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
        final spec = await _findInstalledSpec(fileName);
        final actualName = spec?['name'] as String? ?? fileName;
        final canonicalName =
            _findCanonicalName(actualName, modelType) ?? actualName;
        final model = InstalledModel(
          id: canonicalName,
          fileName: canonicalName,
          modelType: modelType,
          installedAt: DateTime.now(),
          fileSizeBytes: await _getFileSize(dir.path, fileName),
        );
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

      _statusController.add('Downloading $fileName...');
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/nova_download_${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );

      final hfToken = await getHuggingFaceToken();
      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        if (hfToken != null && hfToken.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $hfToken');
        }
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

        if (totalBytes > 0 && receivedBytes != totalBytes) {
          _statusController.add(
            'Download incomplete: expected $totalBytes bytes, got $receivedBytes',
          );
          try {
            await tempFile.delete();
          } catch (_) {}
          return null;
        }

        // NOTE: SHA-256 hash verification is disabled until real hashes are
        // provided. The placeholder hashes in ModelHashes will cause all
        // downloads to fail verification. To enable, replace with real hashes
        // from HuggingFace model pages.
        //
        // final downloadModel = ModelHuggingFaceURLs.modelFromUrl(url);
        // if (downloadModel != null) {
        //   final expectedHash = ModelHashes.hashFor(downloadModel);
        //   if (expectedHash != null) {
        //     _statusController.add('Verifying ${downloadModel.displayName}...');
        //     final isValid = await _verifySha256(
        //       tempFile,
        //       expectedHash,
        //       onProgress:
        //           onProgress != null ? (p) => onProgress(50 + (p ~/ 2)) : null,
        //     );
        //     if (!isValid) {
        //       _statusController.add(
        //         'File corrupted. Try downloading again or pick a file.',
        //       );
        //       try {
        //         await tempFile.delete();
        //       } catch (_) {}
        //       return null;
        //     }
        //   }
        // }
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

  Future<Map<String, dynamic>?> _findInstalledSpec(String fileName) async {
    final path = await _findModelFile(fileName);
    if (path != null) {
      return {'name': p.basename(path)};
    }
    return null;
  }

  /// Find a model file on disk using consistent basename matching.
  /// Returns the full path if found, null otherwise.
  Future<String?> _findModelFile(String fileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();

      // Check direct path first
      final directFile = File('${dir.path}/$fileName');
      if (await directFile.exists()) {
        return directFile.path;
      }

      // Check models subdirectory with single-pass matching
      final modelsDir = Directory('${dir.path}/models');
      if (await modelsDir.exists()) {
        final baseName = fileName
            .replaceAll('.litertlm', '')
            .replaceAll('.task', '')
            .replaceAll('.gguf', '');

        String? partialMatch;
        await for (final entity in modelsDir.list()) {
          if (entity is File) {
            final entityName = p.basename(entity.path);
            final entityBaseName = entityName
                .replaceAll('.litertlm', '')
                .replaceAll('.task', '')
                .replaceAll('.gguf', '');
            // Exact match on base name (after removing extensions)
            if (entityBaseName == baseName) {
              return entity.path;
            }
            // Track first partial match for fallback
            if (partialMatch == null &&
                (entityBaseName.contains(baseName) ||
                    baseName.contains(entityBaseName))) {
              partialMatch = entity.path;
            }
          }
        }
        // Return partial match if no exact match found
        if (partialMatch != null) {
          return partialMatch;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Find all model files on disk matching the given pattern.
  /// Returns list of file paths.
  Future<List<String>> findAllModelFiles(String pattern) async {
    final results = <String>[];
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/models');
      if (await modelsDir.exists()) {
        final patternLower = pattern.toLowerCase();
        await for (final entity in modelsDir.list()) {
          if (entity is File) {
            final entityName = p.basename(entity.path).toLowerCase();
            if (entityName.contains(patternLower)) {
              results.add(entity.path);
            }
          }
        }
      }
    } catch (_) {}
    return results;
  }

  /// Validate a model file before installation.
  /// Returns null if valid, error message if invalid.
  Future<String?> validateModelFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return 'File does not exist';
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        return 'File is empty';
      }

      // Minimum model file size: 1MB (reasonable for any model)
      if (fileSize < 1024 * 1024) {
        return 'File is too small ($fileSize bytes) - may be corrupted';
      }

      // Maximum reasonable model size: 5GB
      if (fileSize > 5 * 1024 * 1024 * 1024) {
        return 'File is unreasonably large (${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(1)}GB)';
      }

      final fileName = p.basename(filePath);
      final ext = p.extension(fileName).toLowerCase();
      if (ext != '.litertlm' && ext != '.task' && ext != '.gguf') {
        return 'Unsupported file extension: $ext';
      }

      // File looks valid
      return null;
    } catch (e) {
      return 'Error validating file: $e';
    }
  }

  /// Delete a model file from disk given its filename.
  /// Returns true if deleted, false otherwise.
  Future<bool> _deleteModelFile(String fileName) async {
    try {
      final path = await _findModelFile(fileName);
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<int> _getFileSize(String dirPath, String fileName) async {
    final path = await _findModelFile(fileName);
    if (path != null) {
      return await File(path).length();
    }
    return 0;
  }

  Future<InstalledModel?> installFromFile({
    required String filePath,
    required ModelType modelType,
    required ModelFileType fileType,
    void Function(int progress)? onProgress,
  }) async {
    String canonicalPath = '';

    // Validate the file before attempting installation
    final validationError = await validateModelFile(filePath);
    if (validationError != null) {
      _statusController.add('Invalid model file: $validationError');
      debugPrint(
          'ModelManager: installFromFile validation failed: $validationError');
      return null;
    }

    try {
      _statusController.add('Installing model from file...');

      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        _statusController.add('File not found: $filePath');
        return null;
      }

      final fileName = p.basename(filePath);
      final ext = p.extension(fileName).toLowerCase();

      if (ext != '.litertlm' && ext != '.task' && ext != '.gguf') {
        _statusController.add(
          'Unsupported format: $ext — only .litertlm, .task, and .gguf are supported',
        );
        return null;
      }

      final docsDir = await getApplicationDocumentsDirectory();

      final specName = _deriveBaseName(fileName);
      final canonicalName = _findCanonicalName(specName, modelType) ?? fileName;
      canonicalPath = '${docsDir.path}/$canonicalName';

      bool copied = false;
      if (!await File(canonicalPath).exists()) {
        _statusController.add('Copying model file to app storage...');
        await sourceFile.copy(canonicalPath);
        copied = true;
      }

      try {
        final builder = FlutterGemma.installModel(
          modelType: modelType,
          fileType: fileType,
        ).fromFile(canonicalPath);
        if (onProgress != null) {
          builder.withProgress(onProgress);
        }
        final result = await builder.install();
        final spec = result.spec;

        final model = InstalledModel(
          id: canonicalName,
          fileName: canonicalName,
          modelType: modelType,
          installedAt: DateTime.now(),
          fileSizeBytes: await File(canonicalPath).length(),
        );

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
      } catch (installError) {
        // Installation failed - clean up copied file if we created one
        if (copied && canonicalPath.isNotEmpty) {
          try {
            final copiedFile = File(canonicalPath);
            if (await copiedFile.exists()) {
              await copiedFile.delete();
              debugPrint('Cleaned up failed install: $canonicalPath');
            }
          } catch (_) {}
        }
        rethrow; // Re-throw to let caller handle the install error
      }
    } catch (e) {
      _statusController.add('Install failed: $e');
      debugPrint('ModelManager: installFromFile failed: $e');
      return null;
    }
  }

  /// Replicates flutter_gemma's filename base-name extraction so we can
  /// compute the canonical install path BEFORE calling into flutter_gemma.
  /// This avoids a post-install rename that would invalidate flutter_gemma's
  /// internal path mappings.
  static String _deriveBaseName(String filename) {
    String result = filename;
    const extensions = [
      '.task',
      '.bin',
      '.tflite',
      '.json',
      '.model',
      '.litertlm',
    ];
    for (final ext in extensions) {
      result = result.replaceAll(ext, '');
    }
    return result;
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
    final path = await _findModelFile(fileName);
    return path != null;
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
    final wasAlreadyInstalled = existing.isNotEmpty;

    bool success = false;
    int actualSize = fileSizeBytes;

    // Always call install() - even if already tracked, we need to ensure
    // flutter_gemma has the model active. The install() call is idempotent.
    try {
      await FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromFile(filePath).install();
      success = true;
    } catch (e) {
      debugPrint('registerDiskModel: install failed: $e');
      // Try finding alternative in models/ directory
      if (wasAlreadyInstalled) {
        // If we already had this model tracked but install failed,
        // don't delete the file - it might just be a flutter_gemma state issue
        rethrow;
      }
      final altPath = await _findModelFile(fileName);
      if (altPath != null && altPath != filePath) {
        try {
          actualSize = await File(altPath).length();
          await FlutterGemma.installModel(
            modelType: modelType,
            fileType: fileType,
          ).fromFile(altPath).install();
          success = true;
        } catch (e2) {
          debugPrint('registerDiskModel: fallback path also failed: $e2');
          await _deleteModelFile(fileName);
          rethrow;
        }
      } else {
        await _deleteModelFile(fileName);
        rethrow;
      }
    }

    // success is only true here if we didn't rethrow above
    if (success) {
      final model = InstalledModel(
        id: fileName,
        fileName: fileName,
        modelType: modelType,
        installedAt: DateTime.now(),
        fileSizeBytes: actualSize,
      );
      _installedModels.removeWhere((m) => m.id == fileName);
      _installedModels.add(model);
      await _saveToPrefs();
      _statusController.add('Registered: $fileName');
    }
  }

  static Future<String?> getHuggingFaceToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_hfTokenKey);
    if (token != null && token.isNotEmpty) return token;
    return null;
  }

  static Future<void> setHuggingFaceToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_hfTokenKey);
    } else {
      await prefs.setString(_hfTokenKey, token);
    }
  }

  static Future<bool> hasHuggingFaceToken() async {
    final token = await getHuggingFaceToken();
    return token != null && token.isNotEmpty;
  }

  /// Verify all installed models are present and loadable.
  /// Returns a list of issues found (empty if all OK).
  Future<List<String>> verifyInstalledModels() async {
    final issues = <String>[];

    for (final model in List<InstalledModel>.from(_installedModels)) {
      final path = await _findModelFile(model.fileName);
      if (path == null) {
        issues.add('${model.fileName}: file not found on disk');
        continue;
      }

      // Check file size matches
      final actualSize = await File(path).length();
      if (actualSize != model.fileSizeBytes) {
        issues.add(
          '${model.fileName}: size mismatch (tracked: ${model.fileSizeBytes}, actual: $actualSize)',
        );
      }

      // Try to validate the file
      final validationError = await validateModelFile(path);
      if (validationError != null) {
        issues.add('${model.fileName}: $validationError');
      }
    }

    return issues;
  }

  /// Repair installed models list by removing entries for missing files.
  /// Returns number of entries removed.
  Future<int> repairInstalledModels() async {
    int removed = 0;
    final toRemove = <InstalledModel>[];

    for (final model in _installedModels) {
      final path = await _findModelFile(model.fileName);
      if (path == null) {
        toRemove.add(model);
      }
    }

    for (final model in toRemove) {
      _installedModels.removeWhere((m) => m.id == model.id);
      removed++;
      debugPrint('Removed missing model from tracking: ${model.fileName}');
    }

    if (removed > 0) {
      await _saveToPrefs();
      _statusController.add('Removed $removed invalid model entries');
    }

    return removed;
  }

  /// Get detailed info about all model files on disk (for debugging).
  Future<Map<String, dynamic>> getStorageInfo() async {
    final info = <String, dynamic>{
      'trackedModels': _installedModels.length,
      'models': <Map<String, dynamic>>[],
    };

    final dir = await getApplicationDocumentsDirectory();

    // Info about tracked models
    for (final model in _installedModels) {
      final path = await _findModelFile(model.fileName);
      info['models'].add({
        'name': model.fileName,
        'trackedSize': model.fileSizeBytes,
        'actualPath': path,
        'exists': path != null,
      });
    }

    // Info about files in models directory
    final modelsDir = Directory('${dir.path}/models');
    if (await modelsDir.exists()) {
      final files = <Map<String, dynamic>>[];
      await for (final entity in modelsDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          files.add({
            'name': p.basename(entity.path),
            'size': stat.size,
            'modified': stat.modified.toIso8601String(),
          });
        }
      }
      info['modelFiles'] = files;
    }

    return info;
  }
}

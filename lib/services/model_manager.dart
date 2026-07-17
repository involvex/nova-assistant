import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/utils/agent_debug_log.dart';

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
  static const _customModelsPrefsKey = 'custom_models';
  static const _hfTokenKey = 'hf_token';
  final List<InstalledModel> _installedModels = [];
  final List<CustomModel> _customModels = [];

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  List<InstalledModel> get installedModels =>
      List.unmodifiable(_installedModels);

  List<CustomModel> get customModels => List.unmodifiable(_customModels);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_prefsKey);
    if (jsonList != null) {
      _installedModels.clear();
      for (final json in jsonList) {
        try {
          final map = jsonDecode(json) as Map<String, dynamic>;
          _installedModels.add(InstalledModel.fromJson(map));
        } catch (e) {
          debugPrint('ModelManager: failed to parse installed model entry: $e');
        }
      }
    }

    final customJsonList = prefs.getStringList(_customModelsPrefsKey);
    if (customJsonList != null) {
      _customModels.clear();
      for (final json in customJsonList) {
        try {
          final map = jsonDecode(json) as Map<String, dynamic>;
          _customModels.add(CustomModel.fromJson(map));
        } catch (e) {
          debugPrint('ModelManager: failed to parse custom model entry: $e');
        }
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

  Future<void> _saveCustomModelsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _customModels.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(_customModelsPrefsKey, jsonList);
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

      // #region agent log
      await AgentDebugLog.log(
        hypothesisId: 'H1-H3',
        location: 'model_manager.dart:installFromNetwork:start',
        message: 'installFromNetwork started',
        data: {
          'url': url,
          'fileName': fileName,
          'modelType': modelType.name,
        },
      );
      // #endregion

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
        final modelPath = await _findModelFile(fileName) ?? fileOnDisk.path;
        final fileSize = await File(modelPath).length();
        final canonicalName =
            _findCanonicalName(fileName, modelType) ?? fileName;

        // #region agent log
        await AgentDebugLog.log(
          hypothesisId: 'H1',
          location: 'model_manager.dart:installFromNetwork:foundOnDisk',
          message: 'Early disk path with deferInstall=true',
          data: {
            'modelPath': modelPath,
            'fileSize': fileSize,
            'canonicalName': canonicalName,
            'fileOnDiskExists': await fileOnDisk.exists(),
          },
        );
        // #endregion

        onProgress?.call(90);
        _statusController.add('Registering model found on disk...');
        try {
          await registerDiskModel(
            filePath: modelPath,
            fileName: canonicalName,
            modelType: modelType,
            fileType: fileType,
            fileSizeBytes: fileSize,
            deferInstall: true,
          );
        } catch (e) {
          debugPrint('ModelManager: registerDiskModel on early disk path: $e');
        }

        final model = InstalledModel(
          id: canonicalName,
          fileName: canonicalName,
          modelType: modelType,
          installedAt: DateTime.now(),
          fileSizeBytes: fileSize,
        );
        _installedModels.removeWhere(
          (m) => m.fileName == canonicalName || m.fileName == fileName,
        );
        _installedModels.add(model);
        await _saveToPrefs();
        onProgress?.call(100);
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

        if (response.statusCode == 401 || response.statusCode == 403) {
          _statusController.add(
            'Download failed: HuggingFace auth required. '
            'Add your HF token in Settings.',
          );
          return null;
        }

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
            // Reserve 90–100% for install/registration
            onProgress((receivedBytes * 90 ~/ totalBytes).clamp(0, 90));
          }
        }
        await sink.close();

        if (totalBytes > 0 && receivedBytes != totalBytes) {
          _statusController.add(
            'Download incomplete: expected $totalBytes bytes, got $receivedBytes',
          );
          try {
            await tempFile.delete();
          } catch (e) {
            debugPrint(
              'ModelManager: failed to delete temp file after incomplete download: $e',
            );
          }
          return null;
        }
      } finally {
        client.close();
      }

      onProgress?.call(92);
      _statusController.add('Installing $fileName...');

      // Delegate to installFromFile — copies to docs dir, registers with
      // flutter_gemma, and renames to canonical filename.
      final installed = await installFromFile(
        filePath: tempFile.path,
        modelType: modelType,
        fileType: fileType,
        onProgress: onProgress == null
            ? null
            : (p) => onProgress(92 + (p * 8 ~/ 100).clamp(0, 8)),
      );

      if (installed != null) {
        onProgress?.call(100);
      }

      // #region agent log
      await AgentDebugLog.log(
        hypothesisId: 'H3',
        location: 'model_manager.dart:installFromNetwork:done',
        message: 'installFromNetwork finished',
        data: {
          'success': installed != null,
          'installedFileName': installed?.fileName,
          'installedSize': installed?.fileSizeBytes,
          'prefsCount': _installedModels.length,
          'prefsNames': _installedModels.map((m) => m.fileName).toList(),
        },
      );
      // #endregion

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (e) {
        debugPrint(
          'ModelManager: failed to delete temp file after install: $e',
        );
      }
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
    } catch (e) {
      debugPrint('ModelManager._findModelFile error: $e');
    }
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
    } catch (e) {
      debugPrint('ModelManager._findAllModelFiles error: $e');
    }
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
    } catch (e) {
      debugPrint('ModelManager._deleteModelFile error: $e');
    }
    return false;
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
        'ModelManager: installFromFile validation failed: $validationError',
      );
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

      if (ext != '.litertlm' && ext != '.task') {
        _statusController.add(
          'Unsupported format: $ext — only .litertlm and .task are supported',
        );
        return null;
      }

      final docsDir = await getApplicationDocumentsDirectory();

      final cleanedName = _stripTempDownloadPrefix(fileName);
      final specName = _deriveBaseName(cleanedName);
      final canonicalName =
          _findCanonicalName(cleanedName, modelType) ??
          _findCanonicalName(specName, modelType) ??
          cleanedName;
      canonicalPath = '${docsDir.path}/$canonicalName';

      // #region agent log
      await AgentDebugLog.log(
        hypothesisId: 'H2-H4',
        location: 'model_manager.dart:installFromFile:canonical',
        message: 'Resolved canonical install name',
        data: {
          'sourceFileName': fileName,
          'cleanedName': cleanedName,
          'canonicalName': canonicalName,
          'modelType': modelType.name,
        },
        runId: 'post-fix',
      );
      // #endregion

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
          } catch (e) {
            debugPrint('ModelManager: failed to clean up failed install: $e');
          }
        }
        rethrow; // Re-throw to let caller handle the install error
      }
    } catch (e) {
      _statusController.add('Install failed: $e');
      debugPrint('ModelManager: installFromFile failed: $e');
      return null;
    }
  }

  Future<CustomModel?> installCustomModel({
    required String filePath,
    required String displayName,
    required ModelType modelType,
    required ModelFileType fileType,
    bool hasVision = false,
    bool hasThinking = false,
    bool supportsFunctionCalling = true,
    bool isGguf = false,
    void Function(int progress)? onProgress,
  }) async {
    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        _statusController.add('File not found: $filePath');
        return null;
      }

      final fileName = p.basename(filePath);
      final ext = p.extension(fileName).toLowerCase();

      if (ext != '.litertlm' && ext != '.task' && ext != '.gguf') {
        _statusController.add(
          'Unsupported format: $ext — only .litertlm and .task are supported',
        );
        return null;
      }

      // GGUF cannot be used for inference with flutter_gemma
      if (ext == '.gguf' || isGguf) {
        _statusController.add(
          'GGUF is not supported for inference — use .litertlm or .task',
        );
        return null;
      }

      // Call installFromFile to copy and register with flutter_gemma
      final installed = await installFromFile(
        filePath: filePath,
        modelType: modelType,
        fileType: fileType,
        onProgress: onProgress,
      );

      if (installed == null) {
        return null;
      }

      final customModel = CustomModel(
        id: displayName,
        displayName: displayName,
        fileName: installed.fileName,
        modelType: modelType,
        fileType: fileType,
        hasVision: hasVision,
        hasThinking: hasThinking,
        supportsFunctionCalling: supportsFunctionCalling,
        fileSizeBytes: installed.fileSizeBytes,
        installedAt: DateTime.now(),
      );

      _customModels.removeWhere(
        (m) => m.id == displayName || m.fileName == installed.fileName,
      );
      _customModels.add(customModel);
      await _saveCustomModelsToPrefs();

      _statusController.add('Custom model installed: $displayName');
      return customModel;
    } catch (e) {
      _statusController.add('Custom model install failed: $e');
      debugPrint('ModelManager: installCustomModel failed: $e');
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

  /// Strip temp download prefixes like `nova_download_<ms>_`.
  static String _stripTempDownloadPrefix(String filename) {
    return filename.replaceFirst(RegExp(r'^nova_download_\d+_'), '');
  }

  /// Find the canonical filename for a model given its flutter_gemma spec name
  /// and model type.
  ///
  /// Matches exact names, and also temp download names that *contain* a known
  /// catalog basename (e.g. `nova_download_123_gemma-4-E2B-it.litertlm`).
  String? _findCanonicalName(String specName, ModelType modelType) {
    final rawBase = p.basename(specName);
    final cleaned = _stripTempDownloadPrefix(rawBase);
    final normalizedSpec = cleaned
        .replaceAll('.litertlm', '')
        .replaceAll('.task', '')
        .toLowerCase();

    // Pass 1: exact match (cleaned name)
    for (final model in NovaModel.values) {
      if (model.modelType != modelType) continue;
      final canonical = ModelHuggingFaceURLs.fileNameFor(model);
      final normalizedCanonical = canonical
          .replaceAll('.litertlm', '')
          .replaceAll('.task', '')
          .toLowerCase();
      if (normalizedSpec == normalizedCanonical) {
        return canonical;
      }
    }

    // Pass 2: full filename with extension equals canonical
    final withExt = cleaned.toLowerCase();
    for (final model in NovaModel.values) {
      if (model.modelType != modelType) continue;
      final canonical = ModelHuggingFaceURLs.fileNameFor(model);
      if (canonical.toLowerCase() == withExt) {
        return canonical;
      }
    }

    // Pass 3: temp/partial names that contain the catalog basename
    // (safe: catalog names are specific; do NOT match reverse contains)
    for (final model in NovaModel.values) {
      if (model.modelType != modelType) continue;
      final canonical = ModelHuggingFaceURLs.fileNameFor(model);
      final normalizedCanonical = canonical
          .replaceAll('.litertlm', '')
          .replaceAll('.task', '')
          .toLowerCase();
      if (normalizedCanonical.isNotEmpty &&
          (normalizedSpec.endsWith(normalizedCanonical) ||
              normalizedSpec.contains(normalizedCanonical))) {
        return canonical;
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

  Future<bool> removeCustomModel(String modelId) async {
    try {
      final customModel = _customModels.firstWhere(
        (m) => m.id == modelId,
        orElse: () => throw Exception('Model not found'),
      );

      // Uninstall from flutter_gemma using the fileName
      await FlutterGemma.uninstallModel(customModel.fileName);
      _customModels.removeWhere((m) => m.id == modelId);
      await _saveCustomModelsToPrefs();
      _statusController.add('Custom model removed: $modelId');
      return true;
    } catch (e) {
      debugPrint('ModelManager: removeCustomModel failed: $e');
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

  /// Public path lookup for models already on disk.
  Future<String?> findModelPath(String fileName) => _findModelFile(fileName);

  bool isCustomModelInstalled(String fileName) {
    return _customModels.any((m) => m.fileName == fileName);
  }

  CustomModel? getCustomModelByFileName(String fileName) {
    try {
      return _customModels.firstWhere((m) => m.fileName == fileName);
    } catch (_) {
      return null;
    }
  }

  /// Register a model already on disk (no download).
  ///
  /// If [deferInstall] is false (default), registers with flutter_gemma
  /// immediately by calling `FlutterGemma.installModel().fromFile().install()`.
  /// This makes the model available for inference.
  ///
  /// If [deferInstall] is true, skips the flutter_gemma registration and just
  /// tracks the model in Nova's internal list. Use this during prefetch to
  /// avoid loading models into GPU memory at startup. The model will be
  /// properly registered when actually needed.
  Future<void> registerDiskModel({
    required String filePath,
    required String fileName,
    required ModelType modelType,
    required ModelFileType fileType,
    required int fileSizeBytes,
    bool deferInstall = false,
  }) async {
    final existing = _installedModels.where((m) => m.fileName == fileName);
    final wasAlreadyInstalled = existing.isNotEmpty;

    // Verify the file exists and has content
    final file = File(filePath);
    if (!await file.exists()) {
      if (!wasAlreadyInstalled) {
        await _deleteModelFile(fileName);
      }
      throw Exception('Model file not found: $filePath');
    }

    final actualSize = await file.length();
    if (actualSize == 0) {
      if (!wasAlreadyInstalled) {
        await _deleteModelFile(fileName);
      }
      throw Exception('Model file is empty: $filePath');
    }

    // If deferring install, just track the model without loading it
    if (deferInstall) {
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
      _statusController.add('Registered (lazy): $fileName');
      return;
    }

    // Actually install with flutter_gemma (loads model into memory)
    bool success = false;
    int registeredSize = actualSize;

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
          registeredSize = await File(altPath).length();
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
        fileSizeBytes: registeredSize,
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

  /// Repair installed models list by removing entries for missing files,
  /// and renaming leftover `nova_download_*` files to catalog names.
  /// Returns number of entries removed.
  Future<int> repairInstalledModels() async {
    await _repairMisnamedTempDownloads();

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

  /// Rename files like `nova_download_<ms>_gemma-4-E2B-it.litertlm` to the
  /// catalog name and fix prefs so the orchestrator can find them.
  Future<void> _repairMisnamedTempDownloads() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final docs = Directory(dir.path);
      if (!await docs.exists()) return;

      final entities = await docs.list().toList();
      for (final entity in entities) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('nova_download_')) continue;
        if (!name.endsWith('.litertlm') && !name.endsWith('.task')) continue;

        final cleaned = _stripTempDownloadPrefix(name);
        ModelType? matchedType;
        String? canonical;
        for (final model in NovaModel.values) {
          final candidate = ModelHuggingFaceURLs.fileNameFor(model);
          final candidateBase = candidate
              .replaceAll('.litertlm', '')
              .replaceAll('.task', '')
              .toLowerCase();
          final cleanedLower = cleaned.toLowerCase();
          if (cleanedLower == candidate.toLowerCase() ||
              cleanedLower.contains(candidateBase)) {
            matchedType = model.modelType;
            canonical = candidate;
            break;
          }
        }
        if (canonical == null || matchedType == null) continue;

        final dest = File(p.join(dir.path, canonical));
        if (!await dest.exists()) {
          await entity.rename(dest.path);
          debugPrint('Repair: renamed $name → $canonical');
        } else {
          await entity.delete();
          debugPrint('Repair: deleted duplicate temp file $name');
        }

        final size = await dest.length();
        _installedModels.removeWhere(
          (m) => m.fileName == name || m.fileName == canonical,
        );
        _installedModels.add(
          InstalledModel(
            id: canonical,
            fileName: canonical,
            modelType: matchedType,
            installedAt: DateTime.now(),
            fileSizeBytes: size,
          ),
        );
        await _saveToPrefs();

        // #region agent log
        await AgentDebugLog.log(
          hypothesisId: 'H2-H4',
          location: 'model_manager.dart:_repairMisnamedTempDownloads',
          message: 'Repaired misnamed temp download',
          data: {'from': name, 'to': canonical, 'size': size},
          runId: 'post-fix',
        );
        // #endregion
      }
    } catch (e) {
      debugPrint('ModelManager: _repairMisnamedTempDownloads failed: $e');
    }
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

  /// Dispose resources
  Future<void> dispose() async {
    await _statusController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';

/// Information about an available model update
class ModelUpdateInfo {
  final NovaModel model;
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final int fileSizeBytes;
  final String? releaseNotes;
  final DateTime publishedAt;

  const ModelUpdateInfo({
    required this.model,
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.fileSizeBytes,
    this.releaseNotes,
    required this.publishedAt,
  });

  double get fileSizeMB => fileSizeBytes / (1024 * 1024);
  bool get isNewer => currentVersion != latestVersion;

  Map<String, dynamic> toJson() => {
    'model': model.name,
    'currentVersion': currentVersion,
    'latestVersion': latestVersion,
    'downloadUrl': downloadUrl,
    'fileSizeBytes': fileSizeBytes,
    'releaseNotes': releaseNotes,
    'publishedAt': publishedAt.toIso8601String(),
  };

  factory ModelUpdateInfo.fromJson(Map<String, dynamic> json) {
    return ModelUpdateInfo(
      model: NovaModel.values.firstWhere(
        (e) => e.name == json['model'],
        orElse: () => NovaModel.smollm,
      ),
      currentVersion: json['currentVersion'] as String,
      latestVersion: json['latestVersion'] as String,
      downloadUrl: json['downloadUrl'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int,
      releaseNotes: json['releaseNotes'] as String?,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
    );
  }
}

/// Service for checking and managing model updates
class ModelUpdateService {
  static ModelUpdateService? _instance;
  static ModelUpdateService get instance =>
      _instance ??= ModelUpdateService._();
  ModelUpdateService._();

  static const _lastCheckKey = 'last_update_check';
  static const _knownVersionsKey = 'known_model_versions';

  final _updatesController =
      StreamController<List<ModelUpdateInfo>>.broadcast();
  Stream<List<ModelUpdateInfo>> get updatesStream => _updatesController.stream;

  List<ModelUpdateInfo> _availableUpdates = [];
  List<ModelUpdateInfo> get availableUpdates =>
      List.unmodifiable(_availableUpdates);

  bool _isChecking = false;
  bool get isChecking => _isChecking;

  /// Check for updates for all installed models
  Future<List<ModelUpdateInfo>> checkForUpdates() async {
    if (_isChecking) return _availableUpdates;

    _isChecking = true;
    _availableUpdates = [];

    try {
      final installedModels = ModelManager.instance.installedModels;
      final knownVersions = await _loadKnownVersions();

      for (final installed in installedModels) {
        try {
          final update = await _checkModelUpdate(installed, knownVersions);
          if (update != null && update.isNewer) {
            _availableUpdates.add(update);
          }
        } catch (e) {
          debugPrint(
            'ModelUpdateService: Error checking ${installed.fileName}: $e',
          );
        }
      }

      await _saveLastCheckTime();
      _updatesController.add(_availableUpdates);
      return _availableUpdates;
    } finally {
      _isChecking = false;
    }
  }

  /// Check if updates are available without performing a full check
  Future<bool> hasUpdates() async {
    final lastCheck = await _getLastCheckTime();
    if (lastCheck == null) return true;

    // Check at most once per day
    final daysSinceLastCheck = DateTime.now().difference(lastCheck).inDays;
    return daysSinceLastCheck >= 1;
  }

  /// Get the time since last update check
  Future<Duration?> getTimeSinceLastCheck() async {
    final lastCheck = await _getLastCheckTime();
    if (lastCheck == null) return null;
    return DateTime.now().difference(lastCheck);
  }

  /// Download and install an update
  Future<bool> installUpdate(
    ModelUpdateInfo update, {
    void Function(int progress)? onProgress,
  }) async {
    try {
      debugPrint(
        'ModelUpdateService: Installing update for ${update.model.displayName}',
      );

      // Install the new version
      final installed = await ModelManager.instance.installFromNetwork(
        url: update.downloadUrl,
        modelType: update.model.modelType,
        fileType: update.model.fileType,
        onProgress: onProgress,
      );

      if (installed == null) {
        return false;
      }

      // Update known version
      await _updateKnownVersion(update.model, update.latestVersion);

      // Remove from available updates
      _availableUpdates.removeWhere((u) => u.model == update.model);
      _updatesController.add(_availableUpdates);

      return true;
    } catch (e) {
      debugPrint('ModelUpdateService: Failed to install update: $e');
      return false;
    }
  }

  /// Dismiss an update (don't remind about this version)
  Future<void> dismissUpdate(ModelUpdateInfo update) async {
    await _updateKnownVersion(update.model, update.latestVersion);
    _availableUpdates.removeWhere((u) => u.model == update.model);
    _updatesController.add(_availableUpdates);
  }

  /// Check a specific model for updates
  Future<ModelUpdateInfo?> _checkModelUpdate(
    InstalledModel installed,
    Map<String, String> knownVersions,
  ) async {
    // Get the NovaModel enum for this installed model
    final novaModel = _novaModelForType(installed.modelType);
    if (novaModel == null) return null;

    // Get the current HuggingFace URL for this model
    final url = ModelHuggingFaceURLs.urlFor(novaModel);
    if (url.isEmpty) return null;

    // For now, we'll check if the model's URL has changed or if we have new version info
    // In a real implementation, this would query a version API
    final currentKnownVersion = knownVersions[installed.fileName];

    // Simulate version check - in production, this would query HuggingFace API
    // or a custom version endpoint
    final latestVersion = await _fetchLatestVersion(novaModel);
    if (latestVersion == null) return null;

    return ModelUpdateInfo(
      model: novaModel,
      currentVersion: currentKnownVersion ?? '1.0.0',
      latestVersion: latestVersion,
      downloadUrl: url,
      fileSizeBytes: installed.fileSizeBytes,
      publishedAt: DateTime.now(),
    );
  }

  /// Convert ModelType to NovaModel
  NovaModel? _novaModelForType(ModelType type) {
    for (final model in NovaModel.values) {
      if (model.modelType == type) return model;
    }
    return null;
  }

  /// Fetch the latest version for a model from HuggingFace
  Future<String?> _fetchLatestVersion(NovaModel model) async {
    try {
      // In production, this would query the HuggingFace API
      // For now, return a simulated version
      final response = await http
          .get(
            Uri.parse(
              'https://huggingface.co/api/models/${_repoForModel(model)}',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Extract version from model info
        return data['lastModified'] as String? ?? '1.0.0';
      }
    } catch (e) {
      debugPrint('ModelUpdateService: Failed to fetch version: $e');
    }
    return null;
  }

  /// Get the HuggingFace repo for a model
  String _repoForModel(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return 'litert-community/SmolLM-135M-Instruct';
      case NovaModel.fastvlm:
        return 'litert-community/FastVLM-0.5B';
      case NovaModel.gemma3_1b:
        return 'litert-community/Gemma3-1B-IT';
      case NovaModel.gemma4E2b:
        return 'litert-community/gemma-4-E2B-it-litert-lm';
    }
  }

  /// Load known model versions from preferences
  Future<Map<String, String>> _loadKnownVersions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_knownVersionsKey);
    if (jsonString == null) return {};

    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// Save a known model version
  Future<void> _updateKnownVersion(NovaModel model, String version) async {
    final versions = await _loadKnownVersions();
    versions[model.name] = version;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_knownVersionsKey, jsonEncode(versions));
  }

  /// Get the last check time
  Future<DateTime?> _getLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastCheckKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Save the last check time
  Future<void> _saveLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Dispose resources
  void dispose() {
    _updatesController.close();
  }
}

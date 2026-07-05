import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Status of a download operation
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// Information about a download in progress
class DownloadInfo {
  final String id;
  final String modelId;
  final String url;
  final String fileName;
  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? error;
  final int retryCount;

  const DownloadInfo({
    required this.id,
    required this.modelId,
    required this.url,
    required this.fileName,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.error,
    this.retryCount = 0,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;
  double get progressPercent => (progress * 100).clamp(0, 100);
  bool get isComplete => status == DownloadStatus.completed;
  bool get isActive => status == DownloadStatus.downloading;
  bool get isPaused => status == DownloadStatus.paused;
  bool get canResume =>
      status == DownloadStatus.paused || status == DownloadStatus.failed;

  Duration get elapsed => DateTime.now().difference(startedAt);
  Duration? get estimatedRemaining {
    if (progress <= 0 || progress >= 1) return null;
    final totalEstimated = Duration(
      milliseconds: (elapsed.inMilliseconds / progress).round(),
    );
    final remaining = totalEstimated - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  DownloadInfo copyWith({
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    DateTime? completedAt,
    String? error,
    int? retryCount,
  }) {
    return DownloadInfo(
      id: id,
      modelId: modelId,
      url: url,
      fileName: fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      error: error ?? this.error,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'modelId': modelId,
    'url': url,
    'fileName': fileName,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'status': status.name,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'error': error,
    'retryCount': retryCount,
  };

  factory DownloadInfo.fromJson(Map<String, dynamic> json) {
    return DownloadInfo(
      id: json['id'] as String,
      modelId: json['modelId'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      totalBytes: json['totalBytes'] as int,
      downloadedBytes: json['downloadedBytes'] as int,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.pending,
      ),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      error: json['error'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }
}

/// Service for tracking download progress and enabling resume
class DownloadProgressService {
  static DownloadProgressService? _instance;
  static DownloadProgressService get instance =>
      _instance ??= DownloadProgressService._();
  DownloadProgressService._();

  static const _downloadsKey = 'active_downloads';
  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 5);

  final Map<String, DownloadInfo> _activeDownloads = {};
  final _downloadsController =
      StreamController<Map<String, DownloadInfo>>.broadcast();
  Stream<Map<String, DownloadInfo>> get downloadsStream =>
      _downloadsController.stream;

  Map<String, DownloadInfo> get activeDownloads =>
      Map.unmodifiable(_activeDownloads);

  /// Initialize the service and restore any interrupted downloads
  Future<void> initialize() async {
    await _restoreDownloads();
  }

  /// Start tracking a new download
  Future<DownloadInfo> startDownload({
    required String modelId,
    required String url,
    required String fileName,
    int totalBytes = 0,
  }) async {
    final id = '${modelId}_${DateTime.now().millisecondsSinceEpoch}';
    final download = DownloadInfo(
      id: id,
      modelId: modelId,
      url: url,
      fileName: fileName,
      totalBytes: totalBytes,
      downloadedBytes: 0,
      status: DownloadStatus.downloading,
      startedAt: DateTime.now(),
    );

    _activeDownloads[id] = download;
    await _saveDownloads();
    _notifyListeners();

    return download;
  }

  /// Update download progress
  Future<void> updateProgress(String downloadId, int downloadedBytes) async {
    final download = _activeDownloads[downloadId];
    if (download == null) return;

    _activeDownloads[downloadId] = download.copyWith(
      downloadedBytes: downloadedBytes,
    );
    await _saveDownloads();
    _notifyListeners();
  }

  /// Mark a download as completed
  Future<void> completeDownload(String downloadId) async {
    final download = _activeDownloads[downloadId];
    if (download == null) return;

    _activeDownloads[downloadId] = download.copyWith(
      status: DownloadStatus.completed,
      completedAt: DateTime.now(),
      downloadedBytes: download.totalBytes,
    );
    await _saveDownloads();
    _notifyListeners();
  }

  /// Pause a download
  Future<void> pauseDownload(String downloadId) async {
    final download = _activeDownloads[downloadId];
    if (download == null) return;

    _activeDownloads[downloadId] = download.copyWith(
      status: DownloadStatus.paused,
    );
    await _saveDownloads();
    _notifyListeners();
  }

  /// Resume a paused or failed download
  Future<void> resumeDownload(String downloadId) async {
    final download = _activeDownloads[downloadId];
    if (download == null || !download.canResume) return;

    _activeDownloads[downloadId] = download.copyWith(
      status: DownloadStatus.downloading,
    );
    await _saveDownloads();
    _notifyListeners();
  }

  /// Cancel a download
  Future<void> cancelDownload(String downloadId) async {
    final download = _activeDownloads[downloadId];
    if (download == null) return;

    _activeDownloads[downloadId] = download.copyWith(
      status: DownloadStatus.cancelled,
    );
    await _saveDownloads();
    _notifyListeners();
  }

  /// Mark a download as failed with retry support
  Future<bool> failDownload(String downloadId, String error) async {
    final download = _activeDownloads[downloadId];
    if (download == null) return false;

    if (download.retryCount < _maxRetries) {
      // Auto-retry
      _activeDownloads[downloadId] = download.copyWith(
        status: DownloadStatus.failed,
        error: error,
        retryCount: download.retryCount + 1,
      );
      await _saveDownloads();
      _notifyListeners();

      // Schedule retry
      Future.delayed(_retryDelay * (download.retryCount + 1), () {
        resumeDownload(downloadId);
      });

      return true; // Will retry
    } else {
      // Max retries exceeded
      _activeDownloads[downloadId] = download.copyWith(
        status: DownloadStatus.failed,
        error: '$error (max retries exceeded)',
      );
      await _saveDownloads();
      _notifyListeners();
      return false;
    }
  }

  /// Remove a completed or cancelled download from tracking
  Future<void> removeDownload(String downloadId) async {
    _activeDownloads.remove(downloadId);
    await _saveDownloads();
    _notifyListeners();
  }

  /// Clean up old completed downloads
  Future<void> cleanupOldDownloads({
    Duration maxAge = const Duration(days: 7),
  }) async {
    final cutoff = DateTime.now().subtract(maxAge);
    final toRemove = _activeDownloads.entries
        .where(
          (e) =>
              e.value.isComplete &&
              e.value.completedAt != null &&
              e.value.completedAt!.isBefore(cutoff),
        )
        .map((e) => e.key)
        .toList();

    for (final id in toRemove) {
      _activeDownloads.remove(id);
    }
    await _saveDownloads();
    _notifyListeners();
  }

  /// Get download info for a specific model
  DownloadInfo? getDownloadForModel(String modelId) {
    try {
      return _activeDownloads.values.firstWhere(
        (d) => d.modelId == modelId && d.isActive,
      );
    } catch (_) {
      return null;
    }
  }

  /// Check if a model is currently being downloaded
  bool isDownloading(String modelId) {
    return _activeDownloads.values.any(
      (d) => d.modelId == modelId && d.isActive,
    );
  }

  /// Get the byte offset for resuming a download
  int getResumeOffset(String downloadId) {
    final download = _activeDownloads[downloadId];
    return download?.downloadedBytes ?? 0;
  }

  /// Save downloads to persistent storage
  Future<void> _saveDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final downloads = _activeDownloads.values
        .where((d) => d.isActive || d.isPaused)
        .map((d) => jsonEncode(d.toJson()))
        .toList();
    await prefs.setStringList(_downloadsKey, downloads);
  }

  /// Restore downloads from persistent storage
  Future<void> _restoreDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final downloadsJson = prefs.getStringList(_downloadsKey);
    if (downloadsJson == null) return;

    for (final json in downloadsJson) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        final download = DownloadInfo.fromJson(map);

        // Only restore paused or failed downloads (can be resumed)
        if (download.isPaused || download.status == DownloadStatus.failed) {
          _activeDownloads[download.id] = download;
        }
      } catch (e) {
        debugPrint('DownloadProgressService: Error restoring download: $e');
      }
    }

    _notifyListeners();
  }

  void _notifyListeners() {
    _downloadsController.add(activeDownloads);
  }

  /// Dispose resources
  void dispose() {
    _downloadsController.close();
  }
}

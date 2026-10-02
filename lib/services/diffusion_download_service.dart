import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:nova_assistant/models/diffusion_model_info.dart';
import 'package:nova_assistant/services/download_progress_service.dart';
import 'package:nova_assistant/services/huggingface_hub_service.dart';

const _chunkSize = 64 * 1024 * 1024;
const _maxConcurrentChunks = 4;
const _progressThrottle = Duration(milliseconds: 200);

class DiffusionDownloadService {
  DiffusionDownloadService._();
  static final DiffusionDownloadService instance = DiffusionDownloadService._();

  final HttpClient _client = HttpClient()
    ..maxConnectionsPerHost = 5
    ..connectionTimeout = const Duration(seconds: 30);

  Future<void> downloadModel({
    required DiffusionModel model,
    required List<HfRepoFile> files,
    required Directory destDir,
    String? hfToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final catalog = DiffusionModelCatalog.forModel(model);
    if (catalog == null) {
      throw Exception('Unknown diffusion model: $model');
    }

    int totalBytes = 0;
    for (final f in files) {
      totalBytes += f.size ?? 0;
    }

    if (totalBytes == 0) {
      throw Exception('Unknown total download size for $model');
    }

    final downloadId =
        'diffusion_${model.name}_${DateTime.now().millisecondsSinceEpoch}';
    await DownloadProgressService.instance.startDownload(
      modelId: model.name,
      url: catalog.repoId,
      fileName: model.fileName,
      totalBytes: totalBytes,
    );

    int receivedBytes = 0;
    DateTime? lastProgressReport;

    Future<void> reportProgress(int delta) async {
      receivedBytes += delta;
      final now = DateTime.now();
      if (onProgress != null &&
          (lastProgressReport == null ||
              now.difference(lastProgressReport!) >= _progressThrottle)) {
        lastProgressReport = now;
        onProgress(receivedBytes, totalBytes);
      }
      await DownloadProgressService.instance.updateProgress(
        downloadId,
        receivedBytes,
      );
    }

    Future<void> downloadFile(HfRepoFile repoFile) async {
      final fileUrl = HuggingfaceHubService.resolveDownloadUrl(
        catalog.repoId,
        path: repoFile.path,
      );
      final destPath = '${destDir.path}/${repoFile.fileName}';
      final uri = Uri.parse(fileUrl);

      final existingFile = File(destPath);
      final alreadyComplete =
          await existingFile.exists() &&
          (repoFile.size == null ||
              (await existingFile.length()) >= repoFile.size!);

      if (alreadyComplete) {
        await reportProgress(repoFile.size ?? 0);
        return;
      }

      final partialSize = await existingFile.exists()
          ? await existingFile.length()
          : 0;
      final supportsRange = await _supportsRangeRequests(uri, hfToken);

      if (supportsRange && partialSize > 0) {
        await _resumeFile(
          uri: uri,
          destPath: destPath,
          partialSize: partialSize,
          totalSize: repoFile.size,
          hfToken: hfToken,
          onProgress: reportProgress,
        );
      } else if (supportsRange && (repoFile.size ?? 0) > _chunkSize) {
        await _downloadFileWithChunks(
          uri: uri,
          destPath: destPath,
          totalSize: repoFile.size!,
          hfToken: hfToken,
          onProgress: reportProgress,
        );
      } else {
        await _downloadFileSingle(
          uri: uri,
          destPath: destPath,
          offset: partialSize,
          hfToken: hfToken,
          onProgress: reportProgress,
        );
      }
    }

    final semaphore = Semaphore(_maxConcurrentChunks);
    final downloadFutures = <Future<void>>[];
    for (final file in files) {
      await semaphore.acquire();
      final future = downloadFile(file).whenComplete(() => semaphore.release());
      downloadFutures.add(future);
    }

    await Future.wait(downloadFutures);

    await DownloadProgressService.instance.completeDownload(downloadId);
    if (onProgress != null) {
      onProgress(totalBytes, totalBytes);
    }
  }

  Future<bool> _supportsRangeRequests(Uri uri, String? hfToken) async {
    try {
      final request = await _client.headUrl(uri);
      if (hfToken != null && hfToken.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $hfToken');
      }
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != 200) return false;
      return response.headers.value(HttpHeaders.acceptRangesHeader) == 'bytes';
    } on Exception {
      return false;
    }
  }

  Future<void> _downloadFileSingle({
    required Uri uri,
    required String destPath,
    required int offset,
    String? hfToken,
    required void Function(int) onProgress,
  }) async {
    final request = await _client.getUrl(uri);
    if (hfToken != null && hfToken.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $hfToken');
    }
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    final response = await request.close();

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode} downloading $uri');
    }

    final sink = offset > 0
        ? File(destPath).openWrite(mode: FileMode.append)
        : File(destPath).openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        onProgress(chunk.length);
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> _downloadFileWithChunks({
    required Uri uri,
    required String destPath,
    required int totalSize,
    String? hfToken,
    required void Function(int) onProgress,
  }) async {
    final chunkCount = (totalSize / _chunkSize).ceil().clamp(2, 8);
    final actualChunkSize = (totalSize / chunkCount).ceil();
    final tempDir = await getTemporaryDirectory();
    final chunksDir = Directory(
      '${tempDir.path}/diffusion_chunks_${DateTime.now().millisecondsSinceEpoch}_${p.basename(uri.path)}',
    );
    await chunksDir.create(recursive: true);

    final chunkFutures = <Future<int>>[];
    for (int i = 0; i < chunkCount; i++) {
      final start = i * actualChunkSize;
      final end = (i == chunkCount - 1)
          ? totalSize - 1
          : ((i + 1) * actualChunkSize) - 1;
      final chunkPath = '${chunksDir.path}/chunk_$i';

      chunkFutures.add(
        _downloadChunk(
          uri: uri,
          chunkPath: chunkPath,
          start: start,
          end: end,
          hfToken: hfToken,
        ),
      );
    }

    final chunkSizes = await Future.wait(chunkFutures);
    for (final size in chunkSizes) {
      onProgress(size);
    }

    final sink = File(destPath).openWrite();
    try {
      for (int i = 0; i < chunkCount; i++) {
        final chunkPath = '${chunksDir.path}/chunk_$i';
        final chunkFile = File(chunkPath);
        final data = await chunkFile.readAsBytes();
        sink.add(data);
      }
    } finally {
      await sink.close();
    }

    try {
      await chunksDir.delete(recursive: true);
    } on Exception {
      // ignore cleanup errors
    }
  }

  Future<int> _downloadChunk({
    required Uri uri,
    required String chunkPath,
    required int start,
    required int end,
    String? hfToken,
  }) async {
    final request = await _client.getUrl(uri);
    if (hfToken != null && hfToken.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $hfToken');
    }
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();

    if (response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode} for range $start-$end');
    }

    final sink = File(chunkPath).openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }

    return File(chunkPath).lengthSync();
  }

  Future<void> _resumeFile({
    required Uri uri,
    required String destPath,
    required int partialSize,
    int? totalSize,
    String? hfToken,
    required void Function(int) onProgress,
  }) async {
    final request = await _client.getUrl(uri);
    if (hfToken != null && hfToken.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $hfToken');
    }
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$partialSize-');
    final response = await request.close();

    if (response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode} resuming $uri');
    }

    final sink = File(destPath).openWrite(mode: FileMode.append);
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        onProgress(chunk.length);
      }
    } finally {
      await sink.close();
    }
  }

  /// Downloads extra assets for a diffusion model from its base checkpoint
  /// (e.g., the Qwen3 tokenizer).
  ///
  /// Only the tokenizer files are fetched here (~11 MB). The source shards
  /// holding `embed_tokens` / `t_embedder` are deliberately NOT downloaded:
  /// they are multi-GB but yield only ~780 MB of host tensors, so
  /// `ZImageTensorExtraction.extractMissingRemote` pulls just those tensors by
  /// HTTP range. Staging whole shards would cost several GB of transfer and
  /// phone storage for the same result.
  ///
  /// Totals are `existing bytes + HEAD sizes of missing files`, so resumed
  /// or partially-present downloads report honest progress. Large fresh
  /// files use parallel range chunks (same path as [downloadModel]).
  Future<void> downloadExtraAssets({
    required DiffusionModel model,
    required DiffusionExtraAssets extraAssets,
    required Directory destDir,
    String? hfToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final jobs = <({String repoId, String upstream, String local})>[
      for (final file in extraAssets.tokenizerFiles)
        (repoId: extraAssets.tokenizerRepoId, upstream: file, local: file),
    ];

    if (jobs.isEmpty) {
      throw Exception('No extra assets defined for $model');
    }

    final Map<String, int> existingLengths = <String, int>{};
    final Map<String, int> remoteSizes = <String, int>{};
    int totalBytes = 0;
    for (final job in jobs) {
      final existsFile = File('${destDir.path}/${job.local}');
      if (await existsFile.exists()) {
        final int len = await existsFile.length();
        existingLengths[job.local] = len;
        totalBytes += len;
      }
    }

    for (final job in jobs) {
      if (existingLengths.containsKey(job.local)) continue;
      final url = HuggingfaceHubService.resolveDownloadUrl(
        job.repoId,
        path: job.upstream,
      );
      final uri = Uri.parse(url);
      try {
        final headRequest = await _client.headUrl(uri);
        if (hfToken != null && hfToken.isNotEmpty) {
          headRequest.headers.set('Authorization', 'Bearer $hfToken');
        }
        final response = await headRequest.close();
        await response.drain<void>();
        if (response.statusCode == 200) {
          final sizeStr = response.headers.value('content-length');
          final size = sizeStr != null ? int.tryParse(sizeStr) ?? 0 : 0;
          if (size > 0) {
            remoteSizes[job.local] = size;
            totalBytes += size;
          }
        }
      } on Exception {
        // HEAD is best-effort; the GET below reports the real failure.
      }
    }

    if (totalBytes == 0) {
      throw Exception(
        'Could not determine total download size for extra assets of '
        '$model — check network access and HuggingFace token for the gated '
        'base checkpoint',
      );
    }

    final downloadId =
        'diffusion_extra_${model.name}_${DateTime.now().millisecondsSinceEpoch}';
    await DownloadProgressService.instance.startDownload(
      modelId: model.name,
      url: extraAssets.tokenizerRepoId,
      fileName: '${model.fileName}_extra_assets',
      totalBytes: totalBytes,
    );

    int receivedBytes = 0;
    DateTime? lastProgressReport;

    Future<void> reportProgress(int delta) async {
      receivedBytes += delta;
      final now = DateTime.now();
      if (onProgress != null &&
          (lastProgressReport == null ||
              now.difference(lastProgressReport!) >= _progressThrottle)) {
        lastProgressReport = now;
        onProgress(receivedBytes, totalBytes);
      }
      await DownloadProgressService.instance.updateProgress(
        downloadId,
        receivedBytes,
      );
    }

    for (final job in jobs) {
      await _downloadSingleFile(
        repoId: job.repoId,
        filePath: job.upstream,
        localPath: job.local,
        destDir: destDir,
        hfToken: hfToken,
        totalSize: existingLengths[job.local] ?? remoteSizes[job.local],
        expectedSize: extraAssets.expectedSizes[job.local],
        onProgress: reportProgress,
      );
    }

    // Fail closed on tampered/truncated bytes while pins exist. Unpinned
    // entries pass vacuously until pins are populated (see the field docs).
    await extraAssets.verifyFilePins(destDir);

    await DownloadProgressService.instance.completeDownload(downloadId);
    if (onProgress != null) {
      onProgress(totalBytes, totalBytes);
    }
  }

  Future<void> _downloadSingleFile({
    required String repoId,
    required String filePath,
    String? localPath,
    required Directory destDir,
    String? hfToken,
    int? totalSize,
    int? expectedSize,
    required void Function(int) onProgress,
  }) async {
    final url = HuggingfaceHubService.resolveDownloadUrl(
      repoId,
      path: filePath,
    );
    final destPath = '${destDir.path}/${localPath ?? filePath}';

    final existingFile = File(destPath);
    if (await existingFile.exists()) {
      final int existingLen = await existingFile.length();
      // A pinned size that no longer matches means truncation/tampering —
      // drop the file so the download below fetches it fresh instead of
      // treating corrupt bytes as complete.
      if (expectedSize != null &&
          expectedSize > 0 &&
          existingLen != expectedSize) {
        debugPrint(
          'DiffusionDownloadService: size drift for $destPath '
          '(expected $expectedSize, got $existingLen) — re-downloading',
        );
        await existingFile.delete();
      } else {
        onProgress(existingLen);
        return;
      }
    }

    final destDirPath = p.dirname(destPath);
    final dir = Directory(destDirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final uri = Uri.parse(url);
    final partialSize = await existingFile.exists()
        ? await existingFile.length()
        : 0;
    final supportsRange = await _supportsRangeRequests(uri, hfToken);

    if (supportsRange && partialSize > 0) {
      await _resumeFile(
        uri: uri,
        destPath: destPath,
        partialSize: partialSize,
        hfToken: hfToken,
        onProgress: onProgress,
      );
    } else if (supportsRange &&
        partialSize == 0 &&
        (totalSize ?? 0) > _chunkSize) {
      await _downloadFileWithChunks(
        uri: uri,
        destPath: destPath,
        totalSize: totalSize!,
        hfToken: hfToken,
        onProgress: onProgress,
      );
    } else {
      await _downloadFileSingle(
        uri: uri,
        destPath: destPath,
        offset: partialSize,
        hfToken: hfToken,
        onProgress: onProgress,
      );
    }
  }
}

class Semaphore {
  Semaphore(int maxPermits) : _available = maxPermits;
  int _available;
  final List<Completer<void>> _waiting = [];

  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      final completer = _waiting.removeAt(0);
      completer.complete();
    } else {
      _available++;
    }
  }
}

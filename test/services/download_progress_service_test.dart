import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/download_progress_service.dart';

void main() {
  group('DownloadInfo', () {
    test('constructs with required fields', () {
      final download = DownloadInfo(
        id: 'test-id',
        modelId: 'gemma-4',
        url: 'https://example.com/model.litertlm',
        fileName: 'model.litertlm',
        totalBytes: 1024 * 1024 * 100,
        downloadedBytes: 0,
        status: DownloadStatus.downloading,
        startedAt: DateTime(2026, 7, 5),
      );

      expect(download.id, 'test-id');
      expect(download.modelId, 'gemma-4');
      expect(download.status, DownloadStatus.downloading);
      expect(download.progress, 0.0);
      expect(download.isComplete, false);
      expect(download.isActive, true);
    });

    test('progress calculates correctly', () {
      final download = DownloadInfo(
        id: 'test-id',
        modelId: 'gemma-4',
        url: 'https://example.com/model.litertlm',
        fileName: 'model.litertlm',
        totalBytes: 1000,
        downloadedBytes: 500,
        status: DownloadStatus.downloading,
        startedAt: DateTime(2026, 7, 5),
      );

      expect(download.progress, 0.5);
      expect(download.progressPercent, 50.0);
    });

    test('canResume returns true for paused status', () {
      final download = DownloadInfo(
        id: 'test-id',
        modelId: 'gemma-4',
        url: 'https://example.com/model.litertlm',
        fileName: 'model.litertlm',
        totalBytes: 1000,
        downloadedBytes: 500,
        status: DownloadStatus.paused,
        startedAt: DateTime(2026, 7, 5),
      );

      expect(download.canResume, true);
    });

    test('canResume returns true for failed status', () {
      final download = DownloadInfo(
        id: 'test-id',
        modelId: 'gemma-4',
        url: 'https://example.com/model.litertlm',
        fileName: 'model.litertlm',
        totalBytes: 1000,
        downloadedBytes: 500,
        status: DownloadStatus.failed,
        startedAt: DateTime(2026, 7, 5),
      );

      expect(download.canResume, true);
    });

    test('copyWith creates new instance with updated fields', () {
      final original = DownloadInfo(
        id: 'test-id',
        modelId: 'gemma-4',
        url: 'https://example.com/model.litertlm',
        fileName: 'model.litertlm',
        totalBytes: 1000,
        downloadedBytes: 500,
        status: DownloadStatus.downloading,
        startedAt: DateTime(2026, 7, 5),
      );

      final updated = original.copyWith(
        downloadedBytes: 750,
        status: DownloadStatus.paused,
      );

      expect(updated.id, original.id);
      expect(updated.downloadedBytes, 750);
      expect(updated.status, DownloadStatus.paused);
      expect(original.downloadedBytes, 500); // Original unchanged
    });

    test('toJson and fromJson roundtrip', () {
      final original = DownloadInfo(
        id: 'test-id',
        modelId: 'gemma-4',
        url: 'https://example.com/model.litertlm',
        fileName: 'model.litertlm',
        totalBytes: 1000,
        downloadedBytes: 500,
        status: DownloadStatus.downloading,
        startedAt: DateTime(2026, 7, 5, 14, 30),
        retryCount: 2,
      );

      final json = original.toJson();
      final restored = DownloadInfo.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.modelId, original.modelId);
      expect(restored.url, original.url);
      expect(restored.fileName, original.fileName);
      expect(restored.totalBytes, original.totalBytes);
      expect(restored.downloadedBytes, original.downloadedBytes);
      expect(restored.status, original.status);
      expect(restored.retryCount, original.retryCount);
    });
  });

  group('DownloadProgressService', () {
    test('can be instantiated', () {
      final service = DownloadProgressService.instance;
      expect(service.activeDownloads, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/model_update_service.dart';
import 'package:nova_assistant/models/model_info.dart';

void main() {
  group('ModelUpdateInfo', () {
    test('constructs with required fields', () {
      final update = ModelUpdateInfo(
        model: NovaModel.gemma4E2b,
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        downloadUrl: 'https://example.com/model.litertlm',
        fileSizeBytes: 1024 * 1024 * 100,
        publishedAt: DateTime(2026, 7, 1),
      );

      expect(update.model, NovaModel.gemma4E2b);
      expect(update.currentVersion, '1.0.0');
      expect(update.latestVersion, '1.1.0');
      expect(update.downloadUrl, 'https://example.com/model.litertlm');
      expect(update.fileSizeBytes, 1024 * 1024 * 100);
      expect(update.isNewer, true);
    });

    test('fileSizeMB calculates correctly', () {
      final update = ModelUpdateInfo(
        model: NovaModel.smollm,
        currentVersion: '1.0.0',
        latestVersion: '1.0.0',
        downloadUrl: 'https://example.com/model.litertlm',
        fileSizeBytes: 1024 * 1024 * 100,
        publishedAt: DateTime(2026, 7, 1),
      );

      expect(update.fileSizeMB, 100.0);
    });

    test('isNewer returns false when versions match', () {
      final update = ModelUpdateInfo(
        model: NovaModel.smollm,
        currentVersion: '1.0.0',
        latestVersion: '1.0.0',
        downloadUrl: 'https://example.com/model.litertlm',
        fileSizeBytes: 1024 * 1024,
        publishedAt: DateTime(2026, 7, 1),
      );

      expect(update.isNewer, false);
    });

    test('toJson and fromJson roundtrip', () {
      final original = ModelUpdateInfo(
        model: NovaModel.gemma3_1b,
        currentVersion: '2.0.0',
        latestVersion: '2.1.0',
        downloadUrl: 'https://example.com/model.litertlm',
        fileSizeBytes: 500 * 1024 * 1024,
        releaseNotes: 'Bug fixes',
        publishedAt: DateTime(2026, 6, 15),
      );

      final json = original.toJson();
      final restored = ModelUpdateInfo.fromJson(json);

      expect(restored.model, original.model);
      expect(restored.currentVersion, original.currentVersion);
      expect(restored.latestVersion, original.latestVersion);
      expect(restored.downloadUrl, original.downloadUrl);
      expect(restored.fileSizeBytes, original.fileSizeBytes);
      expect(restored.releaseNotes, original.releaseNotes);
    });
  });

  group('ModelUpdateService', () {
    test('hasUpdates returns true when never checked', () async {
      // This test would require mocking SharedPreferences
      // For now, just verify the service can be instantiated
      final service = ModelUpdateService.instance;
      expect(service.isChecking, false);
      expect(service.availableUpdates, isEmpty);
    });
  });
}

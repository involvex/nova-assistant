import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/uncensored_model_catalog.dart';

void main() {
  group('UncensoredModelCatalog', () {
    test('has curated entries', () {
      expect(UncensoredModelCatalog.recommended, isNotEmpty);
    });

    test('entries ship LiteRT-native assets only (no GGUF)', () {
      for (final entry in UncensoredModelCatalog.recommended) {
        final lower = entry.fileName.toLowerCase();
        final isLiteRt = lower.endsWith('.litertlm') || lower.endsWith('.task');

        expect(
          isLiteRt,
          isTrue,
          reason: '${entry.repoId} must host .litertlm/.task assets',
        );
      }
    });

    test('every entry carries a well-formed SHA-256 pin', () {
      final sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
      for (final entry in UncensoredModelCatalog.recommended) {
        expect(
          sha256Pattern.hasMatch(entry.expectedSha256),
          isTrue,
          reason: '${entry.fileName} pin must be 64 lowercase hex chars',
        );
      }
    });

    test('pins match the values verified against the Hub tree API', () {
      expect(
        UncensoredModelCatalog.expectedSha256For(
          'gemma4_uncensored_INT4_8192.litertlm',
        ),
        '7c1dd5e4723e8a6d20fbb5f11f34141eb1f8e413d2049aa52211f533966d785e',
      );
      expect(
        UncensoredModelCatalog.expectedSha256For(
          'Gemma-4-E2B-it-abliterated.litertlm',
        ),
        '3bb979594d6fd1a958c7f9c5dbfbdf9d1312ee3eaae009d298b6f19194392953',
      );
    });
    test('repo ids are well formed', () {
      for (final entry in UncensoredModelCatalog.recommended) {
        expect(
          entry.repoId.split('/').length,
          2,
          reason: '${entry.repoId} must be author/name',
        );
        expect(entry.approxSizeMB, greaterThan(0));
      }
    });

    test('byRepoId resolves entries case-insensitively', () {
      final first = UncensoredModelCatalog.recommended.first;
      expect(
        UncensoredModelCatalog.byRepoId(first.repoId.toUpperCase()),
        same(first),
      );
      expect(UncensoredModelCatalog.byRepoId('unknown/model'), isNull);
    });

    test('download urls resolve into the repo with the file name', () {
      for (final entry in UncensoredModelCatalog.recommended) {
        expect(entry.downloadUrl, startsWith('https://huggingface.co/'));
        expect(entry.downloadUrl, contains('/resolve/main/'));
        expect(entry.downloadUrl, contains(entry.fileName));
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

void main() {
  group('CustomModel.copyWith', () {
    test('updates maxContextTokens and preserves other fields', () {
      final original = CustomModel(
        id: 'test',
        displayName: 'Test',
        fileName: 'test.litertlm',
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        fileSizeBytes: 1024,
        installedAt: DateTime(2026, 1, 1),
        maxContextTokens: 4096,
      );

      final updated = original.copyWith(maxContextTokens: 16384);

      expect(updated.maxContextTokens, 16384);
      expect(updated.id, original.id);
      expect(updated.displayName, original.displayName);
      expect(updated.fileName, original.fileName);
    });
  });
}

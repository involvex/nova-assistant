import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Persists generated images under `<docs>/generated_images/` so chat
/// history can reference them by relative path instead of embedding
/// base64 bytes (which previously bloated prefs to 100MB+).
class GeneratedImageStore {
  static const _dirName = 'generated_images';

  static GeneratedImageStore? _instance;
  static GeneratedImageStore get instance =>
      _instance ??= GeneratedImageStore._();

  GeneratedImageStore._();

  /// Writes [bytes] to disk and returns the path relative to the
  /// documents directory, e.g. `generated_images/<uuid>.png`.
  Future<String> save(Uint8List bytes) async {
    final dir = await _ensureDir();
    final fileName = '${const Uuid().v4()}.png';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    return '$_dirName/$fileName';
  }

  /// Reads a stored image; returns null when the file is missing
  /// (e.g. cleared storage) so callers degrade gracefully.
  Future<Uint8List?> read(String relativePath) async {
    try {
      if (!looksLikeStoredImage(relativePath)) return null;

      final file = await resolve(relativePath);
      if (!await file.exists()) return null;

      return await file.readAsBytes();
    } catch (e) {
      debugPrint('GeneratedImageStore.read failed: $e');

      return null;
    }
  }

  Future<File> resolve(String relativePath) async {
    final docs = await getApplicationDocumentsDirectory();

    return File('${docs.path}/$relativePath');
  }

  static bool looksLikeStoredImage(String? path) {
    return path != null &&
        path.startsWith('$_dirName/') &&
        !path.contains('..');
  }

  Future<Directory> _ensureDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }
}

import 'dart:io';

import 'package:crypto/crypto.dart';

/// Hex SHA-256 of [file], streamed so multi-GB shards never sit in memory.
///
/// Used to verify pinned diffusion assets after download.
Future<String> sha256HexOfFile(File file) async {
  final Digest digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nova_assistant/models/diffusion_model_info.dart';
import 'package:nova_assistant/services/huggingface_hub_service.dart';
import 'package:nova_assistant/services/safetensors_extractor.dart';

/// Extracts the Z-Image host tensors from the staged base-checkpoint shards.
///
/// Provenance: `docs/z-image-turbo-litert.md`. The staged shards are the
/// *full* upstream files (`text_encoder/model-00001-of-00003.safetensors`,
/// `transformer/diffusion_pytorch_model-00001-of-00003.safetensors`); the
/// host only needs:
/// - `embed_tokens` `[151936,2560]` bf16 (~778 MB) → [embedTokensFile]
/// - `t_embedder.mlp.{0,2}.{weight,bias}` fp32 (~2 MB) → [tEmbedderFile]
class ZImageTensorExtraction {
  const ZImageTensorExtraction._();

  /// Expected shape of the `embed_tokens` matrix (row-major `[vocab, dim]`).
  static const List<int> embedTokensShape = <int>[151936, 2560];

  /// Exact `t_embedder` tensors (read from the upstream safetensors header).
  static const Map<String, ({String dtype, List<int> shape})> tEmbedderTensors =
      <String, ({String dtype, List<int> shape})>{
        't_embedder.mlp.0.weight': (dtype: 'F32', shape: <int>[1024, 256]),
        't_embedder.mlp.0.bias': (dtype: 'F32', shape: <int>[1024]),
        't_embedder.mlp.2.weight': (dtype: 'F32', shape: <int>[256, 1024]),
        't_embedder.mlp.2.bias': (dtype: 'F32', shape: <int>[256]),
      };

  /// Finds the `embed_tokens` key in a staged text-encoder shard.
  ///
  /// The exact key is checkpoint-dependent (`model.embed_tokens.weight` in
  /// Qwen3-style checkpoints), so this matches the single entry containing
  /// `embed_tokens` with [expectedShape]. Zero matches or ambiguity throws
  /// [StateError] listing what was found.
  static Future<String> findEmbedTokensKey(
    File stagedShard, {
    List<int> expectedShape = embedTokensShape,
  }) async {
    final SafetensorsHeader header = await readSafetensorsHeader(stagedShard);
    final List<String> hits = <String>[];
    header.entries.forEach((String name, SafetensorsTensorEntry entry) {
      if (!name.toLowerCase().contains('embed_tokens')) return;
      if (entry.shape.length != expectedShape.length) return;
      bool same = true;
      for (int i = 0; i < expectedShape.length; i++) {
        if (entry.shape[i] != expectedShape[i]) {
          same = false;
          break;
        }
      }
      if (same) hits.add(name);
    });
    if (hits.length == 1) return hits.single;
    final List<String> names = header.entries.keys.take(12).toList();
    throw StateError(
      'Expected exactly one embed_tokens entry with shape $expectedShape '
      'in ${stagedShard.path}, found ${hits.length} '
      '(e.g. ${names.join(', ')})',
    );
  }

  /// Carves the `embed_tokens` matrix out of the staged text-encoder shard.
  static Future<void> extractEmbedTokens({
    required File source,
    required File dest,
  }) async {
    final String key = await findEmbedTokensKey(source);
    await extractSafetensorsTensors(
      source: source,
      names: <String, String>{key: 'embed_tokens'},
      dest: dest,
    );
  }

  /// Carves the 4 `t_embedder` MLP tensors out of the staged transformer
  /// shard, validating dtype and shape against the documented table.
  static Future<void> extractTEmbedder({
    required File source,
    required File dest,
  }) async {
    final SafetensorsHeader header = await readSafetensorsHeader(source);
    for (final MapEntry<String, ({String dtype, List<int> shape})> want
        in tEmbedderTensors.entries) {
      final SafetensorsTensorEntry? got = header.entries[want.key];
      if (got == null) {
        throw StateError('Tensor "${want.key}" not found in ${source.path}');
      }
      if (got.dtype != want.value.dtype ||
          !_sameShape(got.shape, want.value.shape)) {
        throw StateError(
          'Tensor "${want.key}" is ${got.dtype}${got.shape}, expected '
          '${want.value.dtype}${want.value.shape}',
        );
      }
    }
    await extractSafetensorsTensors(
      source: source,
      names: <String, String>{
        for (final String k in tEmbedderTensors.keys) k: k,
      },
      dest: dest,
    );
  }

  /// Validates the derived files structurally (tensor names, dtypes,
  /// shapes from `docs/z-image-turbo-litert.md`). Byte-exact file pins
  /// cannot be hardcoded — the safetensors JSON header length depends on
  /// the extractor — so shape/dtype checks are the tamper gate here.
  /// Returns false (never throws) when anything is off.
  static Future<bool> verifyDerivedAssets({
    required Directory modelDir,
    required DiffusionExtraAssets assets,
  }) async {
    try {
      if (assets.embedTokensFile.isEmpty || assets.tEmbedderFile.isEmpty) {
        return false;
      }
      final File embed = File('${modelDir.path}/${assets.embedTokensFile}');
      final File tEmbed = File('${modelDir.path}/${assets.tEmbedderFile}');
      if (!await embed.exists() || !await tEmbed.exists()) return false;

      final SafetensorsHeader embedHeader = await readSafetensorsHeader(embed);
      final SafetensorsTensorEntry? matrix =
          embedHeader.entries['embed_tokens'];
      if (matrix == null || !_sameShape(matrix.shape, embedTokensShape)) {
        debugPrint(
          'ZImageTensorExtraction: embed_tokens shape mismatch in '
          '${embed.path}',
        );
        return false;
      }

      final SafetensorsHeader tHeader = await readSafetensorsHeader(tEmbed);
      for (final MapEntry<String, ({String dtype, List<int> shape})> want
          in tEmbedderTensors.entries) {
        final SafetensorsTensorEntry? got = tHeader.entries[want.key];
        if (got == null ||
            got.dtype != want.value.dtype ||
            !_sameShape(got.shape, want.value.shape)) {
          debugPrint(
            'ZImageTensorExtraction: ${want.key} mismatch in ${tEmbed.path}',
          );
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('ZImageTensorExtraction: derived verification failed: $e');
      return false;
    }
  }

  static bool _sameShape(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Extracts whichever derived files are missing for [model], straight from
  /// the upstream shards over HTTP range requests.
  ///
  /// This is the preferred path: the base checkpoint shards are multi-GB, but
  /// the host needs ~780 MB of tensors out of them. Ranged extraction
  /// transfers only the selected byte ranges, so it never stages (or wastes
  /// phone storage on) a full shard. Falls back to [extractMissing] when the
  /// shards were already staged locally.
  ///
  /// Never throws — a false result keeps the caller gated.
  static Future<bool> extractMissingRemote({
    required Directory modelDir,
    required DiffusionModel model,
    String? hfToken,
    HttpClient? client,
    void Function(int received, int total)? onProgress,
  }) async {
    if (model != DiffusionModel.zImageTurbo) return false;
    final DiffusionExtraAssets assets = model.extraAssets;
    final bool owns = client == null;
    final HttpClient http = client ?? HttpClient();
    if (owns) http.connectionTimeout = const Duration(seconds: 30);
    try {
      // Two shards share one progress stream; each job reports its own bytes
      // and `completed` carries earlier jobs forward.
      const int tEmbedderBytes = 1024 * 256 * 4 * 2 + (1024 + 256) * 4;
      final int embedBytes =
          embedTokensShape.fold<int>(1, (int a, int b) => a * b) *
          (SafetensorsTensorEntry.bytesPerElement['BF16'] ?? 2);
      final int total = embedBytes + tEmbedderBytes;
      int completed = 0;

      Future<bool> run({
        required String repoId,
        required String upstream,
        required String derivedRelative,
        required int expectedBytes,
      }) async {
        final bool ok = await _extractRemoteOne(
          modelDir: modelDir,
          repoId: repoId,
          upstream: upstream,
          derivedRelative: derivedRelative,
          token: hfToken,
          client: http,
          onProgress: (int fetched) =>
              onProgress?.call(completed + fetched, total),
        );
        if (ok) {
          completed += expectedBytes;
          onProgress?.call(completed, total);
        }
        return ok;
      }

      final bool embedOk = await run(
        repoId: assets.embedTokensRepoId,
        upstream: assets.embedTokensSource,
        derivedRelative: assets.embedTokensFile,
        expectedBytes: embedBytes,
      );
      final bool tOk = await run(
        repoId: assets.tEmbedderRepoId,
        upstream: assets.tEmbedderSource,
        derivedRelative: assets.tEmbedderFile,
        expectedBytes: tEmbedderBytes,
      );
      return embedOk && tOk;
    } finally {
      if (owns) http.close(force: true);
    }
  }

  static Uri _uriFor(String repoId, String path) =>
      Uri.parse(HuggingfaceHubService.resolveDownloadUrl(repoId, path: path));

  static Future<bool> _extractRemoteOne({
    required Directory modelDir,
    required String repoId,
    required String upstream,
    required String derivedRelative,
    required String? token,
    required HttpClient client,
    required void Function(int) onProgress,
  }) async {
    if (upstream.isEmpty || derivedRelative.isEmpty || repoId.isEmpty) {
      return false;
    }
    final File derived = File('${modelDir.path}/$derivedRelative');
    if (await derived.exists()) return true;
    try {
      final Uri uri = _uriFor(repoId, upstream);
      final SafetensorsHeader header = await readRemoteSafetensorsHeader(
        uri: uri,
        token: token,
        client: client,
      );

      // Validate the header before transferring anything — the embed_tokens
      // range alone is ~780 MB, so a wrong key must fail here, not midway.
      final bool isEmbedTokens = upstream.contains('text_encoder');
      final Map<String, String> names;
      if (isEmbedTokens) {
        final String key = findEmbedTokensKeyInHeader(header);
        names = <String, String>{key: 'embed_tokens'};
      } else {
        _requireTEmbedderShapes(header, upstream);
        names = <String, String>{
          for (final String k in tEmbedderTensors.keys) k: k,
        };
      }

      await extractSafetensorsTensorsRemote(
        uri: uri,
        names: names,
        dest: derived,
        header: header,
        token: token,
        client: client,
        onProgress: (int received, int _) => onProgress(received),
      );
      return await derived.exists();
    } on RangeNotSupportedException catch (e) {
      debugPrint(
        'ZImageTensorExtraction: ranges unavailable for $upstream: $e',
      );
      return false;
    } catch (e) {
      debugPrint('ZImageTensorExtraction: $derivedRelative failed: $e');
      try {
        if (await derived.exists()) await derived.delete();
      } catch (_) {
        // Leave cleanup errors to the next attempt.
      }
      return false;
    }
  }

  /// Validates the documented `t_embedder` dtype/shape table against a header.
  static void _requireTEmbedderShapes(SafetensorsHeader header, String label) {
    for (final MapEntry<String, ({String dtype, List<int> shape})> want
        in tEmbedderTensors.entries) {
      final SafetensorsTensorEntry? got = header.entries[want.key];
      if (got == null) {
        throw StateError('Tensor "${want.key}" not found in $label');
      }
      if (got.dtype != want.value.dtype ||
          !_sameShape(got.shape, want.value.shape)) {
        throw StateError(
          'Tensor "${want.key}" is ${got.dtype}${got.shape}, expected '
          '${want.value.dtype}${want.value.shape}',
        );
      }
    }
  }

  /// Finds the `embed_tokens` key in an already-parsed header.
  static String findEmbedTokensKeyInHeader(
    SafetensorsHeader header, {
    List<int> expectedShape = embedTokensShape,
  }) {
    final List<String> hits = <String>[];
    header.entries.forEach((String name, SafetensorsTensorEntry entry) {
      if (!name.toLowerCase().contains('embed_tokens')) return;
      if (!_sameShape(entry.shape, expectedShape)) return;
      hits.add(name);
    });
    if (hits.length == 1) return hits.single;
    throw StateError(
      'Expected exactly one embed_tokens entry with shape $expectedShape, '
      'found ${hits.length} '
      '(e.g. ${header.entries.keys.take(12).join(', ')})',
    );
  }

  /// Extracts whichever derived files are missing for [model].
  ///
  /// Local-file path: requires the full upstream shards to have been staged
  /// first. Prefer [extractMissingRemote], which needs neither the staging
  /// step nor the extra storage. Skips silently when the staged shard is
  /// absent or the derived file already exists. Returns true when every
  /// derived file now exists. Never throws — callers treat a false result as
  /// "extraction pending" and stay gated.
  static Future<bool> extractMissing({
    required Directory modelDir,
    required DiffusionModel model,
  }) async {
    if (model != DiffusionModel.zImageTurbo) return false;
    final DiffusionExtraAssets assets = model.extraAssets;
    bool ok = true;
    ok =
        await _extractOne(
          modelDir: modelDir,
          stagedRelative: assets.embedTokensSource,
          derivedRelative: assets.embedTokensFile,
          extract: ({required File source, required File dest}) =>
              extractEmbedTokens(source: source, dest: dest),
        ) &&
        ok;
    ok =
        await _extractOne(
          modelDir: modelDir,
          stagedRelative: assets.tEmbedderSource,
          derivedRelative: assets.tEmbedderFile,
          extract: ({required File source, required File dest}) =>
              extractTEmbedder(source: source, dest: dest),
        ) &&
        ok;
    return ok;
  }

  static Future<bool> _extractOne({
    required Directory modelDir,
    required String stagedRelative,
    required String derivedRelative,
    required Future<void> Function({required File source, required File dest})
    extract,
  }) async {
    if (stagedRelative.isEmpty || derivedRelative.isEmpty) return false;
    final File derived = File('${modelDir.path}/$derivedRelative');
    if (await derived.exists()) return true;
    final File staged = File('${modelDir.path}/$stagedRelative');
    if (!await staged.exists()) return false;
    try {
      await extract(source: staged, dest: derived);
      return await derived.exists();
    } catch (e) {
      debugPrint('ZImageTensorExtraction: $derivedRelative failed: $e');
      try {
        if (await derived.exists()) await derived.delete();
      } catch (_) {
        // Leave cleanup errors to the next attempt.
      }
      return false;
    }
  }
}

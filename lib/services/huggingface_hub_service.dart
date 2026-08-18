import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/services/model_manager.dart';

/// A Hugging Face Hub model search hit.
class HfModelHit {
  const HfModelHit({
    required this.id,
    this.author,
    this.downloads = 0,
    this.likes = 0,
    this.pipelineTag,
    this.tags = const [],
    this.gated = false,
  });

  /// Repo id, e.g. `litert-community/FastVLM-0.5B`.
  final String id;
  final String? author;
  final int downloads;
  final int likes;
  final String? pipelineTag;
  final List<String> tags;
  final bool gated;

  String get shortName {
    final slash = id.lastIndexOf('/');
    if (slash < 0 || slash >= id.length - 1) return id;

    return id.substring(slash + 1);
  }

  factory HfModelHit.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((e) => e.toString()).toList()
        : <String>[];
    final gatedRaw = json['gated'];
    final gated =
        gatedRaw == true || gatedRaw == 'auto' || gatedRaw == 'manual';

    return HfModelHit(
      id: json['id'] as String? ?? json['modelId'] as String? ?? '',
      author: json['author'] as String?,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      pipelineTag: json['pipeline_tag'] as String?,
      tags: tags,
      gated: gated,
    );
  }
}

/// A file entry from a Hub repo tree listing.
class HfRepoFile {
  const HfRepoFile({required this.path, this.size, this.type = 'file'});

  final String path;
  final int? size;
  final String type;

  bool get isFile => type == 'file' || type.isEmpty;

  String get fileName {
    final slash = path.lastIndexOf('/');
    if (slash < 0) return path;

    return path.substring(slash + 1);
  }

  factory HfRepoFile.fromJson(Map<String, dynamic> json) {
    return HfRepoFile(
      path: json['path'] as String? ?? '',
      size: (json['size'] as num?)?.toInt(),
      type: json['type'] as String? ?? 'file',
    );
  }
}

/// Inferred install settings for a Hub LiteRT asset.
class HubInstallHints {
  const HubInstallHints({
    required this.displayName,
    required this.modelType,
    required this.fileType,
    required this.hasVision,
    required this.hasThinking,
    required this.maxContextTokens,
  });

  final String displayName;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool hasVision;
  final bool hasThinking;
  final int maxContextTokens;
}

/// Thin Hugging Face Hub REST client for LiteRT model discovery.
class HuggingfaceHubService {
  HuggingfaceHubService({this._client});

  static HuggingfaceHubService? _instance;
  static HuggingfaceHubService get instance =>
      _instance ??= HuggingfaceHubService();

  /// Test-only: replace the singleton (e.g. with a stub).
  @visibleForTesting
  static set instanceForTest(HuggingfaceHubService? value) {
    _instance = value;
  }

  final HttpClient? _client;
  static const litertCommunityAuthor = 'litert-community';

  static const _apiBase = 'https://huggingface.co/api/models';

  /// Builds a direct resolve URL for a file in a Hub repo.
  static String resolveDownloadUrl(
    String repoId, {
    required String path,
    String revision = 'main',
  }) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final encodedRepo = repoId.split('/').map(Uri.encodeComponent).join('/');
    final encodedPath = cleanPath.split('/').map(Uri.encodeComponent).join('/');

    return 'https://huggingface.co/$encodedRepo/resolve/$revision/$encodedPath';
  }

  /// Keeps only LiteRT chat assets (`.litertlm` / `.task`).
  static List<HfRepoFile> filterLiteRtFiles(Iterable<HfRepoFile> files) {
    return files.where((f) {
      if (!f.isFile || f.path.isEmpty) return false;
      final lower = f.path.toLowerCase();

      return lower.endsWith('.litertlm') || lower.endsWith('.task');
    }).toList();
  }

  /// Keeps only LiteRT diffusion assets (`.tflite`).
  static List<HfRepoFile> filterTfliteFiles(Iterable<HfRepoFile> files) {
    return files.where((f) {
      if (!f.isFile || f.path.isEmpty) return false;
      final lower = f.path.toLowerCase();
      return lower.endsWith('.tflite');
    }).toList();
  }

  /// Prefer `.litertlm` over `.task` when both exist; otherwise keep order.
  static List<HfRepoFile> preferLitertlm(List<HfRepoFile> files) {
    final litertlm = files
        .where((f) => f.path.toLowerCase().endsWith('.litertlm'))
        .toList();
    if (litertlm.isNotEmpty) return litertlm;

    return List<HfRepoFile>.from(files);
  }

  /// Heuristics for model type / capabilities from repo + filename.
  static HubInstallHints inferInstallHints({
    required String repoId,
    required String filePath,
    List<String> tags = const [],
  }) {
    final blob = '$repoId $filePath ${tags.join(' ')}'.toLowerCase();
    final fileName = filePath.contains('/')
        ? filePath.substring(filePath.lastIndexOf('/') + 1)
        : filePath;

    final isGemma4 =
        blob.contains('gemma-4') ||
        blob.contains('gemma4') ||
        blob.contains('gemma_4');
    final isGemma3 =
        blob.contains('gemma-3') ||
        blob.contains('gemma3') ||
        blob.contains('gemma_3') ||
        blob.contains('gemmait');

    final hasVision =
        blob.contains('vision') ||
        blob.contains('vlm') ||
        blob.contains('fastvlm') ||
        blob.contains('image-text') ||
        blob.contains('e2b') ||
        blob.contains('e4b');
    final hasThinking = blob.contains('thinking') || isGemma4;

    final modelType = isGemma4
        ? ModelType.gemma4
        : (isGemma3 ? ModelType.gemmaIt : ModelType.general);

    final ext = fileName.toLowerCase().endsWith('.litertlm')
        ? ModelFileType.litertlm
        : ModelFileType.task;

    final displayBase = fileName
        .replaceAll(RegExp(r'\.(litertlm|task)$', caseSensitive: false), '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();

    return HubInstallHints(
      displayName: displayBase.isEmpty ? repoId : displayBase,
      modelType: modelType,
      fileType: ext,
      hasVision: hasVision,
      hasThinking: hasThinking,
      maxContextTokens: isGemma4 ? 8192 : 4096,
    );
  }

  Future<List<HfModelHit>> searchModels({
    String query = '',
    String? author,
    int limit = 30,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'sort': 'downloads',
      'direction': '-1',
    };
    if (query.trim().isNotEmpty) {
      params['search'] = query.trim();
    }
    if (author != null && author.isNotEmpty) {
      params['author'] = author;
    }

    final uri = Uri.parse(_apiBase).replace(queryParameters: params);
    final json = await _getJson(uri);
    if (json is! List) return const [];

    return json
        .whereType<Map<Object?, Object?>>()
        .map((e) => HfModelHit.fromJson(Map<String, dynamic>.from(e)))
        .where((h) => h.id.isNotEmpty)
        .toList();
  }

  /// Lists files under [revision] for [repoId] (recursive when supported).
  Future<List<HfRepoFile>> listRepoFiles(
    String repoId, {
    String revision = 'main',
  }) async {
    final encoded = repoId.split('/').map(Uri.encodeComponent).join('/');
    final uri = Uri.parse('$_apiBase/$encoded/tree/$revision')
        .replace(queryParameters: const {'recursive': '1'});

    final json = await _getJson(uri);
    if (json is! List) return const [];

    return json
        .whereType<Map<Object?, Object?>>()
        .map((e) => HfRepoFile.fromJson(Map<String, dynamic>.from(e)))
        .where((f) => f.path.isNotEmpty)
        .toList();
  }

  /// LiteRT chat files in a repo, preferring `.litertlm`.
  Future<List<HfRepoFile>> listLiteRtFiles(String repoId) async {
    final all = await listRepoFiles(repoId);
    return preferLitertlm(filterLiteRtFiles(all));
  }

  Future<Object?> _getJson(Uri uri) async {
    final token = await ModelManager.getHuggingFaceToken();
    final client = _client ?? HttpClient();
    final ownsClient = _client == null;
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const HfAuthException();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HfHttpException(response.statusCode, body);
      }

      return jsonDecode(body);
    } finally {
      if (ownsClient) client.close();
    }
  }
}

class HfAuthException implements Exception {
  const HfAuthException();

  @override
  String toString() => 'Hugging Face auth required. Add a token in Settings.';
}

class HfHttpException implements Exception {
  const HfHttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'Hugging Face HTTP $statusCode';
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';

class ModelBrowserScreen extends StatefulWidget {
  const ModelBrowserScreen({super.key});

  @override
  State<ModelBrowserScreen> createState() => _ModelBrowserScreenState();
}

class _ModelBrowserScreenState extends State<ModelBrowserScreen> {
  String _status = '';
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _hasSearched = false;

  static const _defaultModels = <Map<String, dynamic>>[
    {
      'id': 'SmolLM-135M',
      'modelId': 'SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
      'author': 'litert-community',
      'downloads': 45000,
      'likes': 320,
      'pipeline_tag': 'text-generation',
      'tags': <String>['gemma', 'smollm', 'fast'],
    },
    {
      'id': 'FastVLM-0.5B',
      'modelId': 'FastVLM-0.5B.litertlm',
      'author': 'litert-community',
      'downloads': 38000,
      'likes': 280,
      'pipeline_tag': 'image-text-to-text',
      'tags': <String>['fastvlm', 'vision', 'fast'],
    },
    {
      'id': 'gemma-3-1b-it-int4',
      'modelId': 'gemma3-1b-it-int4.litertlm',
      'author': 'litert-community',
      'downloads': 52000,
      'likes': 410,
      'pipeline_tag': 'text-generation',
      'tags': <String>['gemma3', 'balanced'],
    },
    {
      'id': 'gemma-4-E2B-it',
      'modelId': 'gemma-4-E2B-it.litertlm',
      'author': 'litert-community',
      'downloads': 28000,
      'likes': 190,
      'pipeline_tag': 'image-text-to-text',
      'tags': <String>['gemma4', 'vision', 'thinking', 'heavy'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }
    _searchModels(query);
  }

  Future<void> _searchModels(String query) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _status = 'Searching HuggingFace...';
    });

    try {
      final token = await ModelManager.getHuggingFaceToken();
      final encoded = Uri.encodeComponent(query);
      final url = 'https://huggingface.co/api/models?search=$encoded&limit=20';
      final uri = Uri.parse(url);

      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        if (token != null && token.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $token');
        }
        final response = await request.close();

        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final List<dynamic> list = jsonDecode(body) as List<dynamic>;
          setState(() {
            _results = list.whereType<Map<String, dynamic>>().where((m) {
              final tags = m['tags'] as List<dynamic>? ?? const [];
              final pipeline = m['pipeline_tag'] as String? ?? '';
              final text =
                  '${m['id']} ${m['author'] ?? ''} $pipeline ${tags.join(' ')}';
              final q = query.toLowerCase();
              return text.toLowerCase().contains(q);
            }).toList();
            _hasSearched = true;
            _status = _results.isEmpty
                ? 'No results found for "$query"'
                : '${_results.length} result(s)';
          });
        } else if (response.statusCode == 401) {
          setState(() {
            _results = [];
            _hasSearched = true;
            _status = 'Auth required. Add a HuggingFace token in Settings.';
          });
        } else {
          setState(() {
            _results = [];
            _hasSearched = true;
            _status = 'Search failed: HTTP ${response.statusCode}';
          });
        }
      } finally {
        client.close();
      }
    } catch (e) {
      setState(() {
        _results = [];
        _hasSearched = true;
        _status = 'Search error: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadModel(Map<String, dynamic> model) async {
    final modelIndex = NovaModel.values.indexWhere(
      (m) => ModelHuggingFaceURLs.fileNameFor(m) == model['modelId'],
    );
    if (modelIndex == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Model type not recognized. Use Settings > Install model from file for custom models.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    final novaModel = NovaModel.values[modelIndex];
    final url = ModelHuggingFaceURLs.urlFor(novaModel);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Download ${novaModel.displayName}?'),
        content: Text(
          'Size: ~${novaModel.sizeMB}MB\nSource: ${Uri.parse(url).host}',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    setState(() {
      _status = 'Downloading ${novaModel.displayName}...';
      _isLoading = true;
    });

    try {
      final installed = await ModelManager.instance.installFromNetwork(
        url: url,
        modelType: novaModel.modelType,
        fileType: novaModel.fileType,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _status = 'Downloading: $progress%');
          }
        },
      );

      if (mounted) {
        setState(() => _status = '');
        if (installed != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Installed: ${installed.fileName}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Download failed. Check Settings > HuggingFace Token or try Install from file.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Model Browser'),
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search HuggingFace for LiteRT models...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _status,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
      );
    }

    if (!_hasSearched) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ..._defaultModels.map((m) => _modelTile(m, isDefault: true)),
        ],
      );
    }

    if (_results.isEmpty && _hasSearched) {
      return Center(
        child: Text(
          'No models found.\nTry a different search term.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final model = _results[index];
        final modelId = model['modelId'] as String? ?? model['id'] as String;
        final isInstalled = ModelManager.instance.isModelInstalled(modelId);
        return _modelTile(model, isInstalled: isInstalled);
      },
    );
  }

  Widget _modelTile(Map<String, dynamic> model,
      {bool isDefault = false, bool isInstalled = false}) {
    final modelId = model['modelId'] as String? ?? model['id'] as String;
    final author = model['author'] as String? ?? 'unknown';
    final downloads = (model['downloads'] as int?) ?? 0;
    final likes = (model['likes'] as int?) ?? 0;
    final pipeline = model['pipeline_tag'] as String? ?? '';

    final novaModel = _findNovaModel(modelId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInstalled
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: novaModel?.hasVision == true
                    ? [const Color(0xFF6C63FF), const Color(0xFF9D4EDD)]
                    : [Colors.grey[700]!, Colors.grey[600]!],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              novaModel?.hasVision == true
                  ? Icons.image_outlined
                  : Icons.text_fields,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modelId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'by $author',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    if (downloads > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${downloads ~/ 1000}k downloads',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                    if (likes > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.thumb_up_outlined,
                          size: 10, color: Colors.grey[600]),
                      Text(
                        '$likes',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
                if (pipeline.isNotEmpty)
                  Text(
                    pipeline,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          isInstalled
              ? Icon(Icons.check_circle, color: Colors.green[400], size: 20)
              : IconButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (novaModel != null) {
                            _downloadModel(model);
                          } else {
                            _showCustomDownloadDialog(model);
                          }
                        },
                  icon: Icon(
                    isDefault
                        ? Icons.cloud_download_outlined
                        : Icons.download_outlined,
                    color:
                        isDefault ? Colors.grey[600] : const Color(0xFF6C63FF),
                    size: 20,
                  ),
                ),
        ],
      ),
    );
  }

  NovaModel? _findNovaModel(String fileId) {
    for (final model in NovaModel.values) {
      if (ModelHuggingFaceURLs.fileNameFor(model) == fileId) {
        return model;
      }
    }
    return null;
  }

  Future<void> _showCustomDownloadDialog(Map<String, dynamic> model) async {
    final urlController = TextEditingController();
    final nameController =
        TextEditingController(text: model['id'] as String? ?? '');
    final typeController = TextEditingController();

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Download Custom Model',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This model is not in the built-in list.',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Download URL',
                labelStyle: TextStyle(color: Colors.grey[400]),
                hintText: 'https://huggingface.co/...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'File name (with extension)',
                labelStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ignore: deprecated_member_use
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF1A1A2E),
              // ignore: deprecated_member_use
              value: typeController.text.isEmpty ? null : typeController.text,
              decoration: InputDecoration(
                labelText: 'Model Type',
                labelStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'general', child: Text('General (SmolLM, FastVLM)')),
                DropdownMenuItem(
                    value: 'gemmaIt', child: Text('Gemma IT (Gemma 3)')),
                DropdownMenuItem(value: 'gemma4', child: Text('Gemma 4')),
              ],
              onChanged: (v) => typeController.text = v ?? '',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          FilledButton(
            onPressed: () async {
              final url = urlController.text.trim();
              final name = nameController.text.trim();
              final type = typeController.text.trim();
              if (url.isEmpty || name.isEmpty || type.isEmpty) return;

              Navigator.pop(ctx);
              await _downloadCustomModel(url, name, type);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCustomModel(
      String url, String fileName, String modelTypeStr) async {
    ModelType? modelType;
    switch (modelTypeStr) {
      case 'gemmaIt':
        modelType = ModelType.gemmaIt;
      case 'gemma4':
        modelType = ModelType.gemma4;
      default:
        modelType = ModelType.general;
    }

    final ext = fileName.split('.').last.toLowerCase();
    final fileType = switch (ext) {
      'litertlm' => ModelFileType.litertlm,
      _ => ModelFileType.task,
    };

    if (!mounted) return;
    setState(() {
      _status = 'Downloading $fileName...';
      _isLoading = true;
    });

    try {
      final installed = await ModelManager.instance.installFromNetwork(
        url: url,
        modelType: modelType,
        fileType: fileType,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _status = 'Downloading: $progress%');
          }
        },
      );

      if (mounted) {
        setState(() => _status = '');
        if (installed != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Installed: ${installed.fileName}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Download failed. Check URL or add a HuggingFace token in Settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

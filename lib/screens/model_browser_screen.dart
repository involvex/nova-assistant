import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/litert_model_catalog.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/models/uncensored_model_catalog.dart';
import 'package:nova_assistant/screens/custom_model_import_sheet.dart';
import 'package:nova_assistant/services/download_network_gate.dart';
import 'package:nova_assistant/services/huggingface_hub_service.dart';
import 'package:nova_assistant/services/model_manager.dart';

class ModelBrowserScreen extends StatefulWidget {
  const ModelBrowserScreen({super.key});

  @override
  State<ModelBrowserScreen> createState() => _ModelBrowserScreenState();
}

enum _BrowserCategory { recommended, uncensored }

class _ModelBrowserScreenState extends State<ModelBrowserScreen> {
  String _status = '';
  bool _isLoading = false;
  _BrowserCategory _category = _BrowserCategory.recommended;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<HfModelHit> _communityResults = [];
  bool _browseLoaded = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadCommunityBrowse());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      unawaited(_loadCommunityBrowse());

      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_searchModels(query));
    });
  }

  Future<void> _loadCommunityBrowse() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _status = 'Loading litert-community models...';
    });
    try {
      final hits = await HuggingfaceHubService.instance.searchModels(
        author: HuggingfaceHubService.litertCommunityAuthor,
        limit: 40,
      );
      if (!mounted) return;
      setState(() {
        _communityResults = hits;
        _browseLoaded = true;
        _status = hits.isEmpty
            ? 'No community models found (check network / token)'
            : '${hits.length} litert-community model(s)';
      });
    } on HfAuthException {
      if (!mounted) return;
      setState(() {
        _communityResults = [];
        _browseLoaded = true;
        _status = 'Auth required. Add a HuggingFace token in Settings.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _communityResults = [];
        _browseLoaded = true;
        _status = 'Browse error: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchModels(String query) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _status = 'Searching HuggingFace...';
    });
    try {
      final hits = await HuggingfaceHubService.instance.searchModels(
        query: query,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        _communityResults = hits;
        _browseLoaded = true;
        _status = hits.isEmpty
            ? 'No results for "$query"'
            : '${hits.length} result(s)';
      });
    } on HfAuthException {
      if (!mounted) return;
      setState(() {
        _communityResults = [];
        _browseLoaded = true;
        _status = 'Auth required. Add a HuggingFace token in Settings.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _communityResults = [];
        _browseLoaded = true;
        _status = 'Search error: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _ensureTokenIfNeeded({required bool gated}) async {
    if (!gated) return true;
    final has = await ModelManager.hasHuggingFaceToken();
    if (has) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('HuggingFace token required'),
        content: Text(
          'This model is gated. Add a HuggingFace token in Settings '
          'before downloading.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    return go == true && await ModelManager.hasHuggingFaceToken();
  }

  Future<void> _downloadRecommended(RecommendedLiteRtModel entry) async {
    if (!await _ensureTokenIfNeeded(gated: entry.gated)) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Download ${entry.displayName}?'),
        content: Text(
          'Size: ~${entry.approxSizeMB}MB\n'
          'Repo: ${entry.repoId}'
          '${entry.gated ? '\nGated — HF token required' : ''}',
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
    if (confirmed != true || !mounted) return;

    final allowed = await DownloadNetworkGate.instance.confirmDownloadAllowed(
      context,
      sizeHint: '~${entry.approxSizeMB}MB',
    );
    if (!allowed || !mounted) return;

    setState(() {
      _status = 'Downloading ${entry.displayName}...';
      _isLoading = true;
    });
    try {
      final installed = await ModelManager.instance.installFromNetwork(
        url: entry.downloadUrl,
        modelType: entry.modelType,
        fileType: entry.fileType,
        onProgress: (p) {
          if (mounted) setState(() => _status = 'Downloading: $p%');
        },
      );
      if (!mounted) return;
      setState(() => _status = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            installed != null
                ? 'Installed: ${installed.fileName}'
                : 'Download failed. Check Settings > HuggingFace Token.',
          ),
          backgroundColor: installed != null ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openHubRepo(HfModelHit hit) async {
    final known = LiteRtModelCatalog.byRepoId(hit.id);
    if (known != null) {
      await _downloadRecommended(known);

      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Listing LiteRT files in ${hit.id}...';
    });

    try {
      final files = await HuggingfaceHubService.instance.listLiteRtFiles(
        hit.id,
      );
      if (!mounted) return;
      if (files.isEmpty) {
        setState(() => _status = 'No .litertlm / .task files in ${hit.id}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No LiteRT chat files (.litertlm / .task) found in this repo.',
            ),
            backgroundColor: Colors.orange,
          ),
        );

        return;
      }

      final selected = files.length == 1
          ? files.first
          : await _pickLiteRtFile(hit, files);
      if (selected == null || !mounted) return;

      await _installHubFile(hit, selected);
    } on HfAuthException {
      if (!mounted) return;
      setState(() {
        _status = 'Auth required. Add a HuggingFace token in Settings.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'List error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<HfRepoFile?> _pickLiteRtFile(
    HfModelHit hit,
    List<HfRepoFile> files,
  ) async {
    return showModalBottomSheet<HfRepoFile>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Choose LiteRT file — ${hit.shortName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final f = files[index];
                    final hints = HuggingfaceHubService.inferInstallHints(
                      repoId: hit.id,
                      filePath: f.path,
                      tags: hit.tags,
                    );
                    final sizeLabel = f.size != null
                        ? _formatBytes(f.size!)
                        : 'size unknown';

                    return ListTile(
                      title: Text(
                        f.fileName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '$sizeLabel · ${hints.modelType.name}'
                        '${hints.hasVision ? ' · vision' : ''}'
                        '${hints.hasThinking ? ' · thinking' : ''}'
                        ' · ${hints.maxContextTokens} ctx',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(ctx, f),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _installHubFile(HfModelHit hit, HfRepoFile file) async {
    final hints = HuggingfaceHubService.inferInstallHints(
      repoId: hit.id,
      filePath: file.path,
      tags: hit.tags,
    );
    final gated =
        hit.gated || ModelHuggingFaceURLs.urlRequiresHuggingFaceAuth(hit.id);
    if (!await _ensureTokenIfNeeded(gated: gated)) return;
    if (!mounted) return;

    final url = HuggingfaceHubService.resolveDownloadUrl(
      hit.id,
      path: file.path,
    );
    final sizeLabel = file.size != null ? _formatBytes(file.size!) : 'unknown';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Download ${file.fileName}?'),
        content: Text(
          'Repo: ${hit.id}\n'
          'Size: $sizeLabel\n'
          'Type: ${hints.modelType.name}\n'
          'Context: ${hints.maxContextTokens}'
          '${hints.hasVision ? '\nVision' : ''}'
          '${hints.hasThinking ? '\nThinking' : ''}'
          '${gated ? '\nGated — HF token required' : ''}',
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
    if (confirmed != true || !mounted) return;

    final allowed = await DownloadNetworkGate.instance.confirmDownloadAllowed(
      context,
      sizeHint: sizeLabel,
    );
    if (!allowed || !mounted) return;

    setState(() {
      _status = 'Downloading ${file.fileName}...';
      _isLoading = true;
    });
    try {
      final custom = await ModelManager.instance.installHubCustomModel(
        url: url,
        displayName: hints.displayName,
        modelType: hints.modelType,
        fileType: hints.fileType,
        hasVision: hints.hasVision,
        hasThinking: hints.hasThinking,
        maxContextTokens: hints.maxContextTokens,
        onProgress: (p) {
          if (mounted) setState(() => _status = 'Downloading: $p%');
        },
      );
      if (!mounted) return;
      setState(() => _status = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            custom != null
                ? 'Installed: ${custom.displayName}'
                : 'Download failed. Check URL or HuggingFace token.',
          ),
          backgroundColor: custom != null ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Model Browser'),
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh community list',
            onPressed: _isLoading
                ? null
                : () {
                    _searchController.clear();
                    unawaited(_loadCommunityBrowse());
                  },
          ),
          IconButton(
            icon: const Icon(Icons.downloading),
            tooltip: 'Import from file',
            onPressed: _showImportSheet,
          ),
        ],
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _categoryChip(_BrowserCategory.recommended, 'Recommended'),
                const SizedBox(width: 8),
                _categoryChip(_BrowserCategory.uncensored, 'Uncensored'),
              ],
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
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final queryEmpty = _searchController.text.trim().isEmpty;
    if (_category == _BrowserCategory.uncensored) {
      return _buildUncensoredBody(queryEmpty);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (queryEmpty) ...[
          _sectionHeader('Recommended'),
          ...LiteRtModelCatalog.recommended.map(_recommendedTile),
          const SizedBox(height: 12),
          _sectionHeader('litert-community'),
        ],
        if (_isLoading && _communityResults.isEmpty && !_browseLoaded)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            ),
          )
        else if (_communityResults.isEmpty && _browseLoaded)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              queryEmpty
                  ? 'Could not load community models.'
                  : 'No models found.\nTry a different search term.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
          )
        else
          ..._communityResults.map(_hubTile),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildUncensoredBody(bool queryEmpty) {
    final hits = _communityResults
        .where(
          (h) =>
              UncensoredModelCatalog.byRepoId(h.id) == null &&
              HuggingfaceHubService.isUncensoredBlob(
                '${h.id} ${h.tags.join(' ')}',
              ),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionHeader('Curated uncensored · LiteRT'),
        ...UncensoredModelCatalog.recommended.map(_uncensoredTile),
        const SizedBox(height: 4),
        Text(
          'GGUF models cannot run on flutter_gemma — only LiteRT '
          '(.litertlm / .task) conversions are listed.',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        if (!queryEmpty) ...[
          _sectionHeader('Matching Hub repos'),
          if (hits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No uncensored repos in the current results.\n'
                'Try searching e.g. "uncensored litertlm".',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            )
          else
            ...hits.map(_hubTile),
        ] else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Search above to discover more uncensored LiteRT repos.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _categoryChip(_BrowserCategory value, String label) {
    final selected = _category == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _category = value),
      selectedColor: const Color(0xFF6C63FF),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
      showCheckmark: false,
    );
  }

  Widget _uncensoredTile(UncensoredModelEntry entry) {
    final installed = ModelManager.instance.isCustomModelInstalled(
      entry.fileName,
    );

    return _tileShell(
      title: entry.displayName,
      subtitle: entry.description,
      meta:
          '${entry.sizeLabel} · ${entry.modelType.name}'
          '${entry.hasVision ? ' · vision' : ''}'
          '${entry.gated ? ' · gated' : ''}',
      hasVision: entry.hasVision,
      hasThinking: entry.hasThinking,
      gated: entry.gated,
      installed: installed,
      onDownload: _isLoading
          ? null
          : () => unawaited(_downloadUncensored(entry)),
    );
  }

  Future<void> _downloadUncensored(UncensoredModelEntry entry) async {
    if (!await _ensureTokenIfNeeded(gated: entry.gated)) return;
    if (!mounted) return;

    final allowed = await DownloadNetworkGate.instance.confirmDownloadAllowed(
      context,
      sizeHint: '${entry.displayName} (${entry.sizeLabel})',
    );
    if (!allowed || !mounted) return;

    setState(() {
      _status = 'Downloading ${entry.displayName}...';
      _isLoading = true;
    });
    try {
      final custom = await ModelManager.instance.installHubCustomModel(
        url: entry.downloadUrl,
        displayName: entry.displayName,
        modelType: entry.modelType,
        fileType: entry.fileType,
        hasVision: entry.hasVision,
        hasThinking: entry.hasThinking,
        maxContextTokens: entry.maxContextTokens,
        onProgress: (p) {
          if (mounted) setState(() => _status = 'Downloading: $p%');
        },
      );
      if (!mounted) return;
      setState(() => _status = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            custom != null
                ? 'Installed: ${custom.displayName}'
                : 'Download failed. Check connection or HuggingFace token.',
          ),
          backgroundColor: custom != null ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _recommendedTile(RecommendedLiteRtModel entry) {
    final installed = ModelManager.instance.isModelInstalled(entry.fileName);

    return _tileShell(
      title: entry.displayName,
      subtitle: entry.repoId,
      meta:
          '~${entry.approxSizeMB} MB · ${entry.pipelineTag}'
          '${entry.gated ? ' · gated' : ''}',
      hasVision: entry.hasVision,
      hasThinking: entry.hasThinking,
      gated: entry.gated,
      installed: installed,
      onDownload: _isLoading ? null : () => _downloadRecommended(entry),
    );
  }

  Widget _hubTile(HfModelHit hit) {
    final known = LiteRtModelCatalog.byRepoId(hit.id);
    final installed = known != null
        ? ModelManager.instance.isModelInstalled(known.fileName)
        : ModelManager.instance.isCustomModelInstalled(hit.shortName) ||
              ModelManager.instance.customModels.any(
                (c) => hit.id.toLowerCase().contains(
                  c.fileName.toLowerCase().replaceAll('.litertlm', ''),
                ),
              );
    final hints = HuggingfaceHubService.inferInstallHints(
      repoId: hit.id,
      filePath: hit.shortName,
      tags: hit.tags,
    );

    return _tileShell(
      title: hit.id,
      subtitle: 'by ${hit.author ?? 'unknown'}',
      meta:
          '${hit.downloads > 0 ? '${hit.downloads ~/ 1000}k dl · ' : ''}'
          '${hit.pipelineTag ?? 'model'}'
          '${hit.gated ? ' · gated' : ''}',
      hasVision: hints.hasVision || known?.hasVision == true,
      hasThinking: hints.hasThinking || known?.hasThinking == true,
      gated: hit.gated || (known?.gated ?? false),
      installed: installed,
      onDownload: _isLoading ? null : () => unawaited(_openHubRepo(hit)),
    );
  }

  Widget _tileShell({
    required String title,
    required String subtitle,
    required String meta,
    required bool hasVision,
    required bool hasThinking,
    required bool gated,
    required bool installed,
    required VoidCallback? onDownload,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: installed
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
                colors: hasVision
                    ? [const Color(0xFF6C63FF), const Color(0xFF9D4EDD)]
                    : [Colors.grey[700]!, Colors.grey[600]!],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasVision ? Icons.image_outlined : Icons.text_fields,
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
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  meta,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (hasVision) _badge('Vision', Colors.purple),
                    if (hasThinking) _badge('Thinking', Colors.orange),
                    if (gated) _badge('Gated', Colors.amber),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          installed
              ? Icon(Icons.check_circle, color: Colors.green[400], size: 20)
              : IconButton(
                  onPressed: onDownload,
                  icon: const Icon(
                    Icons.cloud_download_outlined,
                    color: Color(0xFF6C63FF),
                    size: 20,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.95)),
      ),
    );
  }

  Future<void> _showImportSheet() async {
    final imported = await showModalBottomSheet<CustomModel>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const CustomModelImportSheet(),
    );

    if (!mounted || imported == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Imported: ${imported.displayName}'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

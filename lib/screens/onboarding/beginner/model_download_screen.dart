import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:nova_assistant/services/memory_diagnostics_service.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/platform_adaptation_service.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';
import 'package:nova_assistant/utils/agent_debug_log.dart';

class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback onDownloadComplete;

  const ModelDownloadScreen({super.key, required this.onDownloadComplete});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  NovaModel _targetModel = NovaModel.smollm;
  bool _resolvedTarget = false;

  double _progress = 0;
  String _status = 'Checking device memory...';
  bool _isComplete = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isBusy = false;

  String get _capabilitiesLabel {
    final parts = <String>[];
    if (_targetModel.hasVision) parts.add('Vision');
    if (_targetModel.hasThinking) parts.add('Thinking');
    parts.add('Chat');
    return parts.join(' + ');
  }

  @override
  void initState() {
    super.initState();
    _resolveTargetAndCheck();
  }

  Future<void> _finishReady() async {
    await UserPreferencesService.instance.setMode(UserMode.beginner);
    ModelOrchestrator.instance.preferredModelType = _targetModel;
    ModelOrchestrator.instance.selector.primaryHeavy = _targetModel;
    ModelOrchestrator.instance.selector.fastModel = NovaModel.smollm;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      widget.onDownloadComplete();
    }
  }

  Future<void> _resolveTargetAndCheck() async {
    final recommended = await PlatformAdaptationService.instance
        .recommendModelForDevice();
    // #region agent log
    await AgentDebugLog.log(
      hypothesisId: 'E',
      location: 'model_download_screen.dart:_resolveTargetAndCheck',
      message: 'Onboarding model recommendation',
      data: {
        'recommended': recommended.displayName,
        'sizeMB': recommended.sizeMB,
        'availMemMb': MemoryDiagnosticsService.instance.lastAvailMemMb,
        'totalMemMb': MemoryDiagnosticsService.instance.lastTotalMemMb,
      },
      runId: 'post-fix',
    );
    // #endregion

    if (!mounted) return;
    setState(() {
      _targetModel = recommended;
      _resolvedTarget = true;
      _status = 'Choose how to install ${recommended.displayName}';
    });
    await _checkExisting();
  }

  Future<void> _checkExisting() async {
    final fileName = ModelHuggingFaceURLs.fileNameFor(_targetModel);
    final path = await ModelManager.instance.findModelPath(fileName);

    if (path != null) {
      final size = await File(path).length();
      await ModelManager.instance.registerDiskModel(
        filePath: path,
        fileName: fileName,
        modelType: _targetModel.modelType,
        fileType: _targetModel.fileType,
        fileSizeBytes: size,
        deferInstall: true,
      );

      if (mounted) {
        setState(() {
          _progress = 100;
          _status = 'Model already installed!';
          _isComplete = true;
        });
        await _finishReady();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _status = 'Choose how to install ${_targetModel.displayName}';
        _progress = 0;
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isBusy = true;
      _progress = 0;
      _hasError = false;
      _status = 'Downloading ${_targetModel.displayName}...';
    });

    try {
      final url = ModelHuggingFaceURLs.urlFor(_targetModel);
      final expected = ModelHuggingFaceURLs.fileNameFor(_targetModel);
      final result = await ModelManager.instance.installFromNetwork(
        url: url,
        modelType: _targetModel.modelType,
        fileType: _targetModel.fileType,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress.toDouble());
          }
        },
      );

      // #region agent log
      await AgentDebugLog.log(
        hypothesisId: 'H2-H4',
        location: 'model_download_screen.dart:_downloadModel:result',
        message: 'Onboarding download finished',
        data: {
          'success': result != null,
          'fileName': result?.fileName,
          'expected': expected,
          'prefsOk': ModelManager.instance.isModelInstalled(expected),
          'diskOk': await ModelManager.instance.isInstalledOnDisk(expected),
        },
        runId: 'post-fix',
      );
      // #endregion

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _progress = 100;
          _status = 'Model ready!';
          _isComplete = true;
          _isBusy = false;
        });
        await _finishReady();
      } else {
        setState(() {
          _isBusy = false;
          _hasError = true;
          _errorMessage = 'Download failed. Please check your connection.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _hasError = true;
          _errorMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _importFromStorage() async {
    setState(() {
      _isBusy = true;
      _hasError = false;
      _status = 'Importing from storage...';
    });

    try {
      final pick = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'task'],
      );
      if (pick == null) return;
      if (pick.files.isEmpty || pick.files.first.path == null) {
        if (mounted) {
          setState(() {
            _isBusy = false;
            _status = 'Choose how to install ${_targetModel.displayName}';
          });
        }
        return;
      }

      final path = pick.files.first.path!;
      final installed = await ModelManager.instance.installFromFile(
        filePath: path,
        modelType: _targetModel.modelType,
        fileType: _targetModel.fileType,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.toDouble());
        },
      );

      if (!mounted) return;

      if (installed != null) {
        setState(() {
          _progress = 100;
          _status = 'Model ready!';
          _isComplete = true;
          _isBusy = false;
        });
        await _finishReady();
      } else {
        setState(() {
          _isBusy = false;
          _hasError = true;
          _errorMessage =
              'Import failed. Select a matching model file '
              '(e.g. ${ModelHuggingFaceURLs.fileNameFor(_targetModel)}).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _hasError = true;
          _errorMessage = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeLabel = '~${_targetModel.sizeMB} MB';
    final subtitle = _resolvedTarget
        ? '${_targetModel.displayName} — download ($sizeLabel) or import a\n'
              'model file you already have. Chosen for this device\'s free RAM.'
        : 'Checking free RAM to pick a model that can actually load...';

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.smart_toy_outlined,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            'Install Nova\'s Brain',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          _buildModelInfo(sizeLabel),
          const SizedBox(height: 32),
          if (_hasError) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isBusy || !_resolvedTarget ? null : _downloadModel,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Retry Download',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            TextButton(
              onPressed: _isBusy || !_resolvedTarget
                  ? null
                  : _importFromStorage,
              child: const Text('Import from storage instead'),
            ),
          ] else if (!_isComplete && !_isBusy) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !_resolvedTarget ? null : _downloadModel,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Download from Hugging Face',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: !_resolvedTarget ? null : _importFromStorage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Import from storage'),
              ),
            ),
          ] else ...[
            _buildProgressBar(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    _status,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isComplete
                          ? const Color(0xFF4CAF50)
                          : Colors.grey[400],
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '${_progress.toInt()}%',
                  style: TextStyle(
                    color: _isComplete
                        ? const Color(0xFF4CAF50)
                        : Colors.grey[400],
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
          const Spacer(),
          if (_isComplete)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF4CAF50),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'All set! Starting Nova...',
                      style: TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (!_hasError && !_isBusy)
            Text(
              'Tip: If you already have the model file, use Import.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildModelInfo(String sizeLabel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            'Model',
            _targetModel.displayName,
            Icons.model_training_outlined,
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Size', sizeLabel, Icons.storage_outlined),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Capabilities',
            _capabilitiesLabel,
            Icons.auto_awesome_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF6C63FF), size: 18),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: constraints.maxWidth * (_progress / 100),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

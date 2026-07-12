import 'package:flutter/material.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';

class ModelDownloadScreen extends StatefulWidget {
  final VoidCallback onDownloadComplete;

  const ModelDownloadScreen({
    super.key,
    required this.onDownloadComplete,
  });

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  static const _targetModel = NovaModel.gemma4E2b;

  double _progress = 0;
  String _status = 'Preparing download...';
  bool _isComplete = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkAndDownload();
  }

  Future<void> _checkAndDownload() async {
    final fileName = ModelHuggingFaceURLs.fileNameFor(_targetModel);
    final alreadyInstalled =
        await ModelManager.instance.isInstalledOnDisk(fileName);

    if (alreadyInstalled) {
      if (mounted) {
        setState(() {
          _progress = 100;
          _status = 'Model already installed!';
          _isComplete = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          widget.onDownloadComplete();
        }
      }
      return;
    }

    await _downloadModel();
  }

  Future<void> _downloadModel() async {
    setState(() {
      _progress = 0;
      _status = 'Downloading Gemma 4 E2B...';
    });

    try {
      final url = ModelHuggingFaceURLs.urlFor(_targetModel);
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

      if (mounted) {
        if (result != null) {
          setState(() {
            _progress = 100;
            _status = 'Model ready!';
            _isComplete = true;
          });

          await UserPreferencesService.instance.setMode(
            UserMode.beginner,
          );

          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            widget.onDownloadComplete();
          }
        } else {
          setState(() {
            _hasError = true;
            _errorMessage = 'Download failed. Please check your connection.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _retryDownload() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });
    await _downloadModel();
  }

  @override
  Widget build(BuildContext context) {
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
            'Downloading Nova\'s Brain',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Gemma 4 E2B — the AI model that powers\nall of Nova\'s capabilities.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          _buildModelInfo(),
          const SizedBox(height: 32),
          if (_hasError) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _retryDownload,
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
          ] else ...[
            _buildProgressBar(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _status,
                  style: TextStyle(
                    color: _isComplete
                        ? const Color(0xFF4CAF50)
                        : Colors.grey[400],
                    fontSize: 13,
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
          else if (!_hasError)
            Text(
              'This may take a few minutes depending on your connection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildModelInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            'Model',
            'Gemma 4 E2B',
            Icons.model_training_outlined,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Size',
            '~2400 MB',
            Icons.storage_outlined,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Capabilities',
            'Vision + Thinking + Function Calling',
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
          child: Icon(
            icon,
            color: const Color(0xFF6C63FF),
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
              ),
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

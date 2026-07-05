import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_manager.dart';

// ignore_for_file: use_build_context_synchronously

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoCapture = true;
  bool _thinkingMode = false;
  bool _voiceInput = true;
  bool _ragMemory = false;
  String _installStatus = '';

  @override
  void initState() {
    super.initState();
    ModelManager.instance.statusStream.listen((status) {
      if (mounted) setState(() => _installStatus = status);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('AI Models'),
          ...NovaModel.values.map((m) => _modelCard(context, model: m)),

          const SizedBox(height: 8),

          // Install from file button
          _actionTile(
            icon: Icons.folder_open,
            title: 'Install model from file',
            subtitle: 'Select a .litertlm or .task file from your device',
            onTap: () => _pickAndInstallModel(context),
          ),

          if (_installStatus.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _installStatus,
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          _sectionHeader('Functionality'),
          _toggleTile(
            icon: Icons.screenshot_monitor_outlined,
            title: 'Auto-capture screen',
            subtitle: 'Automatically capture screen when assistant is invoked',
            value: _autoCapture,
            onChanged: (v) => setState(() => _autoCapture = v),
          ),
          _toggleTile(
            icon: Icons.psychology_outlined,
            title: 'Thinking mode',
            subtitle: 'Show model reasoning before answering',
            value: _thinkingMode,
            onChanged: (v) => setState(() => _thinkingMode = v),
          ),
          _toggleTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Voice input',
            subtitle: 'Enable microphone for voice queries',
            value: _voiceInput,
            onChanged: (v) => setState(() => _voiceInput = v),
          ),
          _toggleTile(
            icon: Icons.auto_awesome,
            title: 'RAG Memory',
            subtitle: 'Remember conversations for contextual answers',
            value: _ragMemory,
            onChanged: (v) => setState(() => _ragMemory = v),
          ),
          const SizedBox(height: 24),

          _sectionHeader('About'),
          _infoTile(
            icon: Icons.info_outline,
            title: 'Nova Assistant',
            subtitle: 'Version 0.1.0 — Powered by Gemma',
          ),
          _infoTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            subtitle:
                'All processing happens on-device. No data leaves your phone.',
          ),
          _infoTile(
            icon: Icons.code,
            title: 'Open Source',
            subtitle: 'Built with Flutter + flutter_gemma',
          ),
          const SizedBox(height: 24),

          _sectionHeader('Data'),
          _actionTile(
            icon: Icons.delete_outline,
            title: 'Clear conversation history',
            subtitle: 'Delete all chat messages',
            onTap: () async {
              await ModelOrchestrator.instance.clearHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('History cleared')),
                );
              }
            },
          ),
          _actionTile(
            icon: Icons.refresh,
            title: 'Reload models',
            subtitle: 'Refresh installed model list',
            onTap: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndInstallModel(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'task', 'bin'],
        dialogTitle: 'Select a model file',
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file path')),
          );
        }
        return;
      }

      // Show model type picker
      if (!context.mounted) return;
      final modelType = await _showModelTypePicker(context);
      if (modelType == null) return;

      // Install
      setState(() => _installStatus = 'Installing ${file.name}...');
      final installed = await ModelManager.instance.installFromFile(
        filePath: file.path!,
        modelType: modelType,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _installStatus = 'Installing: $progress%');
          }
        },
      );

      if (mounted) {
        setState(() => _installStatus = '');
        if (installed != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Model installed: ${installed.fileName}'),
              backgroundColor: Colors.green[700],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to install model'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _installStatus = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<ModelType?> _showModelTypePicker(BuildContext context) {
    return showModalBottomSheet<ModelType>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Model Type',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _modelTypeOption(
              ctx,
              ModelType.general,
              'General',
              'SmolLM, FastVLM, and other general models',
            ),
            _modelTypeOption(
              ctx,
              ModelType.gemmaIt,
              'Gemma IT',
              'Gemma 3 instruction-tuned models',
            ),
            _modelTypeOption(
              ctx,
              ModelType.gemma4,
              'Gemma 4',
              'Gemma 4 models (E2B, etc.)',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _modelTypeOption(
    BuildContext ctx,
    ModelType type,
    String title,
    String subtitle,
  ) {
    return ListTile(
      leading: Icon(
        type == ModelType.gemma4
            ? Icons.auto_awesome
            : type == ModelType.gemmaIt
            ? Icons.smart_toy
            : Icons.psychology,
        color: const Color(0xFF6C63FF),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
      onTap: () => Navigator.pop(ctx, type),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _modelCard(BuildContext context, {required NovaModel model}) {
    final installed = ModelManager.instance.isModelInstalled(
      _fileNameFor(model),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: model.hasVision
                    ? [const Color(0xFF6C63FF), const Color(0xFF9D4EDD)]
                    : [Colors.grey[700]!, Colors.grey[600]!],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              model.hasVision ? Icons.image_outlined : Icons.text_fields,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      model.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${model.sizeMB}MB',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    if (model.hasThinking) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'THINK',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  installed ? 'Installed' : 'Not installed',
                  style: TextStyle(
                    fontSize: 12,
                    color: installed ? Colors.green[400] : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          if (installed)
            Icon(Icons.check_circle, color: Colors.green[400], size: 20)
          else
            Icon(
              Icons.cloud_download_outlined,
              color: Colors.grey[600],
              size: 20,
            ),
        ],
      ),
    );
  }

  String _fileNameFor(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return 'SmolLM-135M-Instruct';
      case NovaModel.fastvlm:
        return 'FastVLM-0.5B';
      case NovaModel.gemma3_1b:
        return 'Gemma3-1B-IT';
      case NovaModel.gemma4E2b:
        return 'gemma-4-E2B-it-int4';
    }
  }

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[400], size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF6C63FF),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[400], size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6C63FF), size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }
}

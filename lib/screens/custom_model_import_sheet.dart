import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:path/path.dart' as p;

class CustomModelImportSheet extends StatefulWidget {
  final void Function(CustomModel model)? onInstalled;

  const CustomModelImportSheet({super.key, this.onInstalled});

  @override
  State<CustomModelImportSheet> createState() => _CustomModelImportSheetState();
}

class _CustomModelImportSheetState extends State<CustomModelImportSheet> {
  String? _selectedFilePath;
  String? _selectedFileName;
  int? _selectedFileSize;
  String? _fileExtension;
  String? _fileError;

  final _nameController = TextEditingController();
  String _modelType = 'general';
  bool _hasVision = false;
  bool _hasThinking = false;
  bool _supportsFunctionCalling = true;
  bool _isInstalling = false;
  String _status = '';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'task'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final path = file.path;

        if (path == null) {
          setState(() => _fileError = 'Could not access file path');

          return;
        }

        final fileSize = file.size;
        final ext = p.extension(file.name).toLowerCase();

        if (ext == '.gguf') {
          setState(
            () => _fileError =
                'GGUF is not supported for inference. '
                'Use .litertlm or .task models instead.',
          );

          return;
        }

        // Validate file
        if (fileSize < 1024 * 1024) {
          setState(() => _fileError = 'File too small (min 1MB)');

          return;
        }

        if (fileSize > 5 * 1024 * 1024 * 1024) {
          setState(() => _fileError = 'File too large (max 5GB)');

          return;
        }

        // Auto-fill name from filename
        String autoName = p.basenameWithoutExtension(file.name);
        autoName = autoName
            .replaceAll('.litertlm', '')
            .replaceAll('.task', '')
            .replaceAll('-', ' ')
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (w) =>
                  w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
            )
            .join(' ');

        setState(() {
          _selectedFilePath = path;
          _selectedFileName = file.name;
          _selectedFileSize = fileSize;
          _fileExtension = ext;
          _fileError = null;
          _nameController.text = autoName;
        });
      }
    } catch (e) {
      setState(() => _fileError = 'Failed to pick file: $e');
    }
  }

  Future<void> _install() async {
    if (_selectedFilePath == null) {
      setState(() => _status = 'Please select a file first');

      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _status = 'Please enter a model name');

      return;
    }

    setState(() {
      _isInstalling = true;
      _status = 'Installing...';
    });

    try {
      ModelType modelType;
      switch (_modelType) {
        case 'gemmaIt':
          modelType = ModelType.gemmaIt;
        case 'gemma4':
          modelType = ModelType.gemma4;
        default:
          modelType = ModelType.general;
      }

      final fileType = _fileExtension == '.task'
          ? ModelFileType.task
          : ModelFileType.litertlm;

      final customModel = await ModelManager.instance.installCustomModel(
        filePath: _selectedFilePath!,
        displayName: name,
        modelType: modelType,
        fileType: fileType,
        hasVision: _hasVision,
        hasThinking: _hasThinking,
        supportsFunctionCalling: _supportsFunctionCalling,
        isGguf: false,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _status = 'Installing: $progress%');
          }
        },
      );

      if (!mounted) return;

      if (customModel != null) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, customModel);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Imported: ${customModel.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _isInstalling = false;
          _status = 'Installation failed. Check file format.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _status = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Text(
                  'Import Custom Model',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // File picker
            Text(
              'Model File',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _fileError != null
                        ? Colors.red
                        : _selectedFilePath != null
                        ? Colors.green
                        : Colors.grey.shade600,
                  ),
                ),
                child: _selectedFilePath != null
                    ? Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade400,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedFileName ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${(_selectedFileSize! / 1024 / 1024).toStringAsFixed(1)} MB',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _pickFile,
                            child: const Text('Change'),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(
                            'Select .litertlm or .task file',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
              ),
            ),
            if (_fileError != null) ...[
              const SizedBox(height: 4),
              Text(
                _fileError!,
                style: TextStyle(color: Colors.red.shade400, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Only .litertlm and .task formats are supported for inference. '
              'GGUF files cannot be run in this app.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),

            // Model name
            TextField(
              controller: _nameController,
              enabled: !_isInstalling,
              decoration: InputDecoration(
                labelText: 'Model Name',
                hintText: 'My Custom Model',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade600),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Model type
            DropdownButtonFormField<String>(
              initialValue: _modelType,
              decoration: InputDecoration(
                labelText: 'Model Type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade600),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'general',
                  child: Text('General (SmolLM, FastVLM)'),
                ),
                DropdownMenuItem(
                  value: 'gemmaIt',
                  child: Text('Gemma IT (Gemma 3)'),
                ),
                DropdownMenuItem(value: 'gemma4', child: Text('Gemma 4')),
              ],
              onChanged: _isInstalling
                  ? null
                  : (v) => setState(() => _modelType = v ?? 'general'),
            ),
            const SizedBox(height: 20),

            // Capabilities
            Text(
              'Capabilities',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Vision'),
                  selected: _hasVision,
                  onSelected: _isInstalling
                      ? null
                      : (v) => setState(() => _hasVision = v),
                  avatar: Icon(
                    Icons.image,
                    size: 16,
                    color: _hasVision ? Colors.purple : Colors.grey,
                  ),
                ),
                FilterChip(
                  label: const Text('Thinking'),
                  selected: _hasThinking,
                  onSelected: _isInstalling
                      ? null
                      : (v) => setState(() => _hasThinking = v),
                  avatar: Icon(
                    Icons.psychology,
                    size: 16,
                    color: _hasThinking ? Colors.orange : Colors.grey,
                  ),
                ),
                FilterChip(
                  label: const Text('Function Calling'),
                  selected: _supportsFunctionCalling,
                  onSelected: _isInstalling
                      ? null
                      : (v) => setState(() => _supportsFunctionCalling = v),
                  avatar: Icon(
                    Icons.code,
                    size: 16,
                    color: _supportsFunctionCalling ? Colors.blue : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Status
            if (_status.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (_isInstalling)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Install button
            FilledButton.icon(
              onPressed: _selectedFilePath != null && !_isInstalling
                  ? _install
                  : null,
              icon: const Icon(Icons.download),
              label: const Text('Import Model'),
            ),
          ],
        ),
      ),
    );
  }
}

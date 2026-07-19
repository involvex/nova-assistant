import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/widgets/custom_model_card.dart';
import 'package:nova_assistant/widgets/model_card.dart';

class ModelSelectorSheet extends StatefulWidget {
  final NovaModel? currentSelection;
  final CustomModel? currentCustomModel;
  final bool isAutoMode;
  final void Function(NovaModel?) onModelSelected;
  final void Function(CustomModel?) onCustomModelSelected;
  final void Function(bool) onAutoModeChanged;
  final VoidCallback? onImportModel;

  const ModelSelectorSheet({
    super.key,
    required this.currentSelection,
    this.currentCustomModel,
    required this.isAutoMode,
    required this.onModelSelected,
    required this.onCustomModelSelected,
    required this.onAutoModeChanged,
    this.onImportModel,
  });

  @override
  State<ModelSelectorSheet> createState() => _ModelSelectorSheetState();
}

class _ModelSelectorSheetState extends State<ModelSelectorSheet> {
  late bool _isAutoMode;
  NovaModel? _selectedModel;
  CustomModel? _selectedCustomModel;
  final Set<NovaModel> _installedModels = {};
  List<CustomModel> _customModels = [];

  @override
  void initState() {
    super.initState();
    _isAutoMode = widget.isAutoMode;
    _selectedModel = widget.currentSelection;
    _selectedCustomModel = widget.currentCustomModel;
    _loadInstalledModels();
    _loadCustomModels();
  }

  Future<void> _loadInstalledModels() async {
    final manager = ModelManager.instance;
    final installed = <NovaModel>{};
    for (final model in NovaModel.values) {
      final fileName = ModelHuggingFaceURLs.fileNameFor(model);
      if (manager.isModelInstalled(fileName)) {
        installed.add(model);
        continue;
      }
      // Disk may have the file even if prefs were cleared / install failed mid-way
      final onDisk = await manager.isInstalledOnDisk(fileName);
      if (onDisk) {
        final path = await manager.findModelPath(fileName);
        if (path != null) {
          try {
            final size = await File(path).length();
            await manager.registerDiskModel(
              filePath: path,
              fileName: fileName,
              modelType: model.modelType,
              fileType: model.fileType,
              fileSizeBytes: size,
              deferInstall: true,
            );
          } catch (_) {
            // Still show as installed if file exists
          }
        }
        installed.add(model);
      }
    }
    if (mounted) {
      setState(() => _installedModels.addAll(installed));
    }
  }

  Future<void> _loadCustomModels() async {
    if (mounted) {
      setState(() {
        _customModels = List.from(ModelManager.instance.customModels);
      });
    }
  }

  Future<void> _deleteCustomModel(CustomModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Custom Model?'),
        content: Text(
          'This will remove "${model.displayName}" from your device. '
          'The model file will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ModelManager.instance.removeCustomModel(model.id);
      if (mounted) {
        setState(() {
          _customModels.removeWhere((m) => m.id == model.id);
          if (_selectedCustomModel?.id == model.id) {
            _selectedCustomModel = null;
            widget.onCustomModelSelected(null);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(theme),
          const Divider(height: 1),
          _buildAutoToggle(theme),
          const SizedBox(height: 8),
          Flexible(child: _buildModelList()),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(
            'Select Model',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (widget.onImportModel != null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Import custom model',
              onPressed: widget.onImportModel,
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoToggle(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.grey.shade800
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildToggleButton(
                label: 'Auto',
                icon: Icons.auto_awesome,
                isSelected: _isAutoMode,
                onTap: () {
                  setState(() => _isAutoMode = true);
                  widget.onAutoModeChanged(true);
                },
              ),
            ),
            Expanded(
              child: _buildToggleButton(
                label: 'Manual',
                icon: Icons.account_tree,
                isSelected: !_isAutoMode,
                onTap: () {
                  setState(() => _isAutoMode = false);
                  widget.onAutoModeChanged(false);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : (theme.brightness == Brightness.dark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (theme.brightness == Brightness.dark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelList() {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (_isAutoMode) _buildAutoExplanation(),

        // Built-in models
        ...NovaModel.values.map((model) {
          final isInstalled = _installedModels.contains(model);
          final isSelected =
              _selectedModel == model && _selectedCustomModel == null;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ModelCard(
              model: model,
              isSelected: isSelected,
              isInstalled: isInstalled,
              onTap: () {
                setState(() {
                  _selectedModel = model;
                  _selectedCustomModel = null;
                  _isAutoMode = false;
                });
                widget.onModelSelected(model);
                widget.onCustomModelSelected(null);
                widget.onAutoModeChanged(false);
              },
            ),
          );
        }),

        // Custom models section
        if (_customModels.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Custom Models',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
              const Spacer(),
              if (widget.onImportModel != null)
                TextButton.icon(
                  onPressed: widget.onImportModel,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ..._customModels.map((model) {
            final isSelected = _selectedCustomModel?.id == model.id;
            final isUnsupported = model.isGguf;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CustomModelCard(
                model: model,
                isSelected: isSelected,
                isDisabled: isUnsupported,
                disabledReason: isUnsupported
                    ? 'Not supported for inference'
                    : null,
                onTap: isUnsupported
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'GGUF models are not supported for inference. '
                              'Use a .litertlm or .task model instead.',
                            ),
                          ),
                        );
                      }
                    : () {
                        setState(() {
                          _selectedModel = null;
                          _selectedCustomModel = model;
                          _isAutoMode = false;
                        });
                        widget.onModelSelected(null);
                        widget.onCustomModelSelected(model);
                        widget.onAutoModeChanged(false);
                      },
                onDelete: () => _deleteCustomModel(model),
              ),
            );
          }),
        ] else if (widget.onImportModel != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.extension, color: Colors.purple.shade300),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No custom models yet',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Import your own .litertlm or .task models',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.onImportModel,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Import'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAutoExplanation() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Auto always uses your device\'s recommended model '
              '(Gemma 3 1B on mid-range phones, Gemma 4 when free RAM allows). '
              'Pick Manual to pin a specific model.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/widgets/model_card.dart';

class ModelSelectorSheet extends StatefulWidget {
  final NovaModel? currentSelection;
  final bool isAutoMode;
  final void Function(NovaModel?) onModelSelected;
  final void Function(bool) onAutoModeChanged;

  const ModelSelectorSheet({
    super.key,
    required this.currentSelection,
    required this.isAutoMode,
    required this.onModelSelected,
    required this.onAutoModeChanged,
  });

  @override
  State<ModelSelectorSheet> createState() => _ModelSelectorSheetState();
}

class _ModelSelectorSheetState extends State<ModelSelectorSheet> {
  late bool _isAutoMode;
  NovaModel? _selectedModel;
  final Set<NovaModel> _installedModels = {};

  @override
  void initState() {
    super.initState();
    _isAutoMode = widget.isAutoMode;
    _selectedModel = widget.currentSelection;
    _loadInstalledModels();
  }

  Future<void> _loadInstalledModels() async {
    final manager = ModelManager.instance;
    final installed = <NovaModel>{};
    for (final model in NovaModel.values) {
      final fileName = ModelHuggingFaceURLs.fileNameFor(model);
      if (manager.isModelInstalled(fileName)) {
        installed.add(model);
      }
    }
    if (mounted) {
      setState(() => _installedModels.addAll(installed));
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(theme),
          const Divider(height: 1),
          _buildAutoToggle(theme),
          const SizedBox(height: 8),
          _buildModelList(),
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
    return Flexible(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (_isAutoMode) _buildAutoExplanation(),
          ...NovaModel.values.map((model) {
            final isInstalled = _installedModels.contains(model);
            final isSelected = _selectedModel == model;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ModelCard(
                model: model,
                isSelected: isSelected,
                isInstalled: isInstalled,
                onTap: () {
                  setState(() {
                    _selectedModel = model;
                    _isAutoMode = false;
                  });
                  widget.onModelSelected(model);
                  widget.onAutoModeChanged(false);
                },
              ),
            );
          }),
        ],
      ),
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
              'Auto uses smart selection based on your query. Vision queries use '
              'Gemma 4 E2B, short queries use SmolLM for speed.',
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

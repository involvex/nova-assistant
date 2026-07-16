import 'package:flutter/material.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/widgets/model_capability_badge.dart';

class ModelCard extends StatelessWidget {
  final NovaModel model;
  final bool isSelected;
  final bool isInstalled;
  final bool showCapabilities;
  final VoidCallback? onTap;

  const ModelCard({
    super.key,
    required this.model,
    this.isSelected = false,
    this.isInstalled = false,
    this.showCapabilities = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              _buildIcon(theme),
              const SizedBox(width: 16),
              Expanded(child: _buildInfo(theme)),
              if (isInstalled)
                Icon(
                  Icons.check_circle,
                  color: Colors.green.shade400,
                  size: 20,
                ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check, color: theme.colorScheme.primary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme) {
    IconData icon;
    Color color;

    if (model.hasThinking) {
      icon = Icons.psychology;
      color = Colors.orange;
    } else if (model.hasVision) {
      icon = Icons.image;
      color = Colors.purple;
    } else if (model == NovaModel.smollm) {
      icon = Icons.flash_on;
      color = Colors.amber;
    } else {
      icon = Icons.smart_toy;
      color = Colors.blue;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildInfo(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          model.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          model.sizeLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
        ),
        if (showCapabilities) ...[
          const SizedBox(height: 8),
          ModelCapabilityBadges(
            hasVision: model.hasVision,
            hasThinking: model.hasThinking,
            isSmall: true,
            isInstalled: isInstalled,
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/widgets/model_capability_badge.dart';

class CustomModelCard extends StatelessWidget {
  final CustomModel model;
  final bool isSelected;
  final bool isDisabled;
  final String? disabledReason;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const CustomModelCard({
    super.key,
    required this.model,
    this.isSelected = false,
    this.isDisabled = false,
    this.disabledReason,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Opacity(
      opacity: isDisabled ? 0.55 : 1,
      child: Material(
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
                if (onDelete != null) ...[
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                    onPressed: onDelete,
                    tooltip: 'Remove custom model',
                  ),
                ],
                if (isSelected && !isDisabled) ...[
                  Icon(Icons.check, color: theme.colorScheme.primary, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme) {
    IconData icon;
    Color color;

    if (model.isGguf || isDisabled) {
      icon = Icons.block;
      color = Colors.grey;
    } else if (model.hasThinking) {
      icon = Icons.psychology;
      color = Colors.orange;
    } else if (model.hasVision) {
      icon = Icons.image;
      color = Colors.purple;
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
        Row(
          children: [
            Expanded(
              child: Text(
                model.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Custom',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.purple.shade300,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          model.sizeLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
        ),
        if (disabledReason != null || model.isGguf) ...[
          const SizedBox(height: 4),
          Text(
            disabledReason ?? 'Not supported for inference',
            style: TextStyle(
              fontSize: 11,
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 8),
        ModelCapabilityBadges(
          hasVision: model.hasVision,
          hasThinking: model.hasThinking,
          isSmall: true,
        ),
      ],
    );
  }
}

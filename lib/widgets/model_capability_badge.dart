import 'package:flutter/material.dart';

enum CapabilityType { vision, thinking, fast, functionCalling }

class ModelCapabilityBadge extends StatelessWidget {
  final CapabilityType type;
  final bool isSupported;
  final bool isSmall;

  const ModelCapabilityBadge({
    super.key,
    required this.type,
    this.isSupported = true,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _iconLabelColor();

    if (!isSupported) {
      return Tooltip(
        message: 'Not supported on this platform',
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 6 : 8,
            vertical: isSmall ? 2 : 4,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: isSmall ? 12 : 14, color: Colors.grey),
              if (!isSmall) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isSmall ? 10 : 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 6 : 8,
        vertical: isSmall ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isSmall ? 12 : 14, color: color),
          if (!isSmall) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: isSmall ? 10 : 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (IconData, String, Color) _iconLabelColor() {
    switch (type) {
      case CapabilityType.vision:
        return (Icons.image, 'Vision', Colors.purple);
      case CapabilityType.thinking:
        return (Icons.psychology, 'Thinking', Colors.orange);
      case CapabilityType.fast:
        return (Icons.flash_on, 'Fast', Colors.amber);
      case CapabilityType.functionCalling:
        return (Icons.extension, 'Functions', Colors.blue);
    }
  }
}

class ModelCapabilityBadges extends StatelessWidget {
  final bool hasVision;
  final bool hasThinking;
  final bool isSmall;
  final bool isInstalled;

  const ModelCapabilityBadges({
    super.key,
    required this.hasVision,
    required this.hasThinking,
    this.isSmall = false,
    this.isInstalled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ModelCapabilityBadge(
          type: CapabilityType.functionCalling,
          isSupported: isInstalled,
          isSmall: isSmall,
        ),
        if (hasVision)
          ModelCapabilityBadge(
            type: CapabilityType.vision,
            isSupported: isInstalled,
            isSmall: isSmall,
          ),
        if (hasThinking)
          ModelCapabilityBadge(
            type: CapabilityType.thinking,
            isSupported: isInstalled,
            isSmall: isSmall,
          ),
      ],
    );
  }
}

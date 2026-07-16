import 'package:flutter/material.dart';
import 'package:nova_assistant/models/user_preferences.dart';

class ModeSelectionScreen extends StatelessWidget {
  final void Function(UserMode mode) onModeSelected;
  final VoidCallback onBack;

  const ModeSelectionScreen({
    super.key,
    required this.onModeSelected,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Choose Your Experience',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select how you want to use Nova',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: Column(
              children: [
                _ModeCard(
                  title: 'Beginner Mode',
                  subtitle: 'Simple & Easy',
                  description: 'Perfect for talking to Nova like a friend.\nJust tap the mic and ask.',
                  icon: Icons.mic_rounded,
                  iconColor: const Color(0xFF4CAF50),
                  features: const [
                    'Large, easy-to-use buttons',
                    'Voice input with one tap',
                    'Automatic model selection',
                    'No complex settings',
                  ],
                  onTap: () => onModeSelected(UserMode.beginner),
                ),
                const SizedBox(height: 20),
                _ModeCard(
                  title: 'Expert Mode',
                  subtitle: 'Full Control',
                  description: 'Access all features including\nscreenshots, files, and custom tools.',
                  icon: Icons.settings_rounded,
                  iconColor: const Color(0xFF6C63FF),
                  features: const [
                    'Manual model selection',
                    'Screenshot & file attachments',
                    'MCP tools & configurations',
                    'Full settings access',
                  ],
                  onTap: () => onModeSelected(UserMode.expert),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color iconColor;
  final List<String> features;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.features,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(color: iconColor, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[600],
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: features.map((f) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D1A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          // Models Section
          _sectionHeader('AI Models'),
          _modelCard(
            context,
            model: NovaModel.gemma4E2b,
            description:
                'Full power — vision, audio, function calling, thinking',
          ),
          _modelCard(
            context,
            model: NovaModel.fastvlm,
            description: 'Fast vision-language model',
          ),
          _modelCard(
            context,
            model: NovaModel.smollm,
            description: 'Ultra-fast for simple queries',
          ),
          const SizedBox(height: 24),

          // Functionality Section
          _sectionHeader('Functionality'),
          _toggleTile(
            icon: Icons.screenshot_monitor_outlined,
            title: 'Auto-capture screen',
            subtitle: 'Automatically capture screen when assistant is invoked',
            value: true,
            onChanged: (v) {},
          ),
          _toggleTile(
            icon: Icons.psychology_outlined,
            title: 'Thinking mode',
            subtitle: 'Show model reasoning before answering',
            value: false,
            onChanged: (v) {},
          ),
          _toggleTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Voice input',
            subtitle: 'Enable microphone for voice queries',
            value: true,
            onChanged: (v) {},
          ),
          _toggleTile(
            icon: Icons.auto_awesome,
            title: 'RAG Memory',
            subtitle: 'Remember conversations for contextual answers',
            value: false,
            onChanged: (v) {},
          ),
          const SizedBox(height: 24),

          // About Section
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

          // Danger Zone
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
            icon: Icons.download_outlined,
            title: 'Manage downloaded models',
            subtitle: 'Free up space by removing unused models',
            onTap: () {
              // Navigate to model management screen
            },
          ),
        ],
      ),
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

  Widget _modelCard(
    BuildContext context, {
    required NovaModel model,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_outline,
            color: const Color(0xFF6C63FF),
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
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
            Icon(icon, color: Colors.red[400], size: 22),
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

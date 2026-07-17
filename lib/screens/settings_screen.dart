import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/models/assistant_language.dart';
import 'package:nova_assistant/models/assistant_role.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:nova_assistant/platform/assistant_role_service.dart';
import 'package:nova_assistant/screens/assistant_screen.dart';
import 'package:nova_assistant/screens/identity_config_screen.dart';
import 'package:nova_assistant/screens/mcp_settings_screen.dart';
import 'package:nova_assistant/screens/knowledge_base_screen.dart';
import 'package:nova_assistant/screens/memory_management_screen.dart';
import 'package:nova_assistant/screens/user_memory_overview_screen.dart';
import 'package:nova_assistant/screens/tasks_screen.dart';
import 'package:nova_assistant/screens/notes_screen.dart';
import 'package:nova_assistant/screens/conversation_search_screen.dart';
import 'package:nova_assistant/screens/model_browser_screen.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/services/tts_service.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';
import 'package:nova_assistant/services/settings_backup_service.dart';
import 'package:nova_assistant/services/memory_diagnostics_service.dart';
import 'package:nova_assistant/screens/prompt_presets_screen.dart';
import 'package:nova_assistant/utils/agent_debug_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _ttsEnabled = true;
  bool _ragMemory = false;
  bool _batteryOptimization = true;
  bool _isAssistantRoleHeld = false;
  bool _debugMode = false;
  String _debugMemoryLabel = 'Tap to refresh';
  AssistantRole _assistantRole = AssistantRole.helpful;
  AssistantLanguage _assistantLanguage = AssistantLanguage.match;
  String _installStatus = '';
  String _appVersion = '0.1.0';
  String _hfTokenStatus = 'Not configured';
  StreamSubscription<Map<String, dynamic>>? _assistantRoleSub;
  StreamSubscription<String>? _modelStatusSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkAssistantRole();
    _assistantRoleSub = AssistantRoleService.instance.onAssistantRoleChanged
        .listen((event) {
          if (event['event'] == 'assistantRoleChanged' && mounted) {
            setState(() => _isAssistantRoleHeld = event['held'] as bool);
          }
        });
    _modelStatusSub = ModelManager.instance.statusStream.listen((status) {
      if (mounted) setState(() => _installStatus = status);
    });
    _loadAppVersion();
  }

  @override
  void dispose() {
    _assistantRoleSub?.cancel();
    _modelStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAssistantRole() async {
    final held = await AssistantRoleService.instance.isAssistantRoleHeld();
    if (mounted) setState(() => _isAssistantRoleHeld = held);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoCapture = prefs.getBool('settings_auto_capture') ?? true;
        _thinkingMode = prefs.getBool('settings_thinking_mode') ?? false;
        _voiceInput = prefs.getBool('settings_voice_input') ?? true;
        _ttsEnabled = prefs.getBool('settings_tts_enabled') ?? true;
        _ragMemory = prefs.getBool('settings_rag_memory') ?? false;
        _batteryOptimization =
            prefs.getBool('settings_battery_optimization') ?? true;
        _debugMode = prefs.getBool('settings_debug_mode') ?? false;
        _assistantRole = AssistantRole.fromString(
          prefs.getString('settings_assistant_role'),
        );
        _assistantLanguage = AssistantLanguage.fromString(
          prefs.getString(AssistantLanguage.prefsKey),
        );
        _hfTokenStatus = _resolveHfTokenStatus(prefs.getString('hf_token'));
      });
      if (_debugMode) {
        unawaited(_refreshDebugMemory());
      }
    }
  }

  Future<void> _refreshDebugMemory() async {
    final mb = await MemoryDiagnosticsService.instance.readProcessMemoryMb();
    if (!mounted) return;
    setState(() {
      _debugMemoryLabel = mb != null
          ? '$mb MB (process PSS/RSS)'
          : 'Unavailable';
    });
  }

  Future<void> _confirmResetInference() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Reset inference engine?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This unloads the on-device model and clears GPU memory. '
          'Use if chat is stuck or after a crash.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ModelOrchestrator.instance.resetInferenceSession();
    await _refreshDebugMemory();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Inference engine reset')));
  }

  String _resolveHfTokenStatus(String? token) {
    if (token == null || token.isEmpty) return 'Not configured';
    final display = token.length > 12
        ? '${token.substring(0, 8)}...${token.substring(token.length - 4)}'
        : token;
    return 'Configured ($display)';
  }

  Future<void> _showHfTokenDialog(BuildContext context) async {
    final controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('hf_token') ?? '';
    controller.text = current;

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'HuggingFace Token',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Required for gated models (e.g. Gemma). '
              'Get yours at huggingface.co/settings/tokens',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'hf_...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (current.isNotEmpty) {
                prefs.remove('hf_token');
              }
              Navigator.pop(ctx);
              setState(() => _hfTokenStatus = 'Not configured');
            },
            child: Text('Remove', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          FilledButton(
            onPressed: () async {
              final token = controller.text.trim();
              await ModelManager.setHuggingFaceToken(
                token.isEmpty ? null : token,
              );
              if (context.mounted) {
                setState(() => _hfTokenStatus = _resolveHfTokenStatus(token));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version}+${info.buildNumber}');
      }
    } catch (e) {
      debugPrint('SettingsScreen._loadAppVersion error: $e');
    }
  }

  Future<void> _saveAssistantRole(AssistantRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings_assistant_role', role.name);
    await prefs.reload();
    await ModelOrchestrator.refreshSettings();
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    // Ensure data is written to disk immediately
    await prefs.reload();
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

          // HuggingFace token
          _actionTile(
            icon: Icons.key,
            title: 'HuggingFace Token',
            subtitle: _hfTokenStatus,
            onTap: () => _showHfTokenDialog(context),
          ),

          // Install from file button
          _actionTile(
            icon: Icons.folder_open,
            title: 'Install model from file',
            subtitle:
                'Select a .litertlm, .task, or .gguf file from your device',
            onTap: () => _pickAndInstallModel(context),
          ),

          _actionTile(
            icon: Icons.explore_outlined,
            title: 'Browse & Download Models',
            subtitle: 'Discover and download models from HuggingFace',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ModelBrowserScreen(),
                ),
              );
              if (context.mounted) {
                setState(() {});
              }
            },
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

          _sectionHeader('Experience'),
          _actionTile(
            icon: Icons.tune_outlined,
            title: 'Switch to Beginner Mode',
            subtitle: 'Simplified UI with basic features',
            onTap: () => _showModeSwitchDialog(context, UserMode.beginner),
          ),
          _actionTile(
            icon: Icons.explore_outlined,
            title: 'Browse & Download Models',
            subtitle: 'Discover and download models from HuggingFace',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ModelBrowserScreen(),
                ),
              );
              if (context.mounted) {
                setState(() {});
              }
            },
          ),

          const SizedBox(height: 24),

          _sectionHeader('Functionality'),
          _toggleTile(
            icon: Icons.screenshot_monitor_outlined,
            title: 'Auto-capture screen',
            subtitle: 'Automatically capture screen when assistant is invoked',
            value: _autoCapture,
            onChanged: (v) {
              setState(() => _autoCapture = v);
              _saveSetting('settings_auto_capture', v);
            },
          ),
          _toggleTile(
            icon: Icons.psychology_outlined,
            title: 'Thinking mode',
            subtitle: 'Show model reasoning before answering',
            value: _thinkingMode,
            onChanged: (v) {
              setState(() => _thinkingMode = v);
              _saveSetting('settings_thinking_mode', v);
            },
          ),
          _toggleTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Voice input',
            subtitle: 'Enable microphone for voice queries',
            value: _voiceInput,
            onChanged: (v) {
              setState(() => _voiceInput = v);
              _saveSetting('settings_voice_input', v);
            },
          ),
          _toggleTile(
            icon: Icons.volume_up_outlined,
            title: 'Speak responses',
            subtitle: 'Show Speak on assistant messages (TTS)',
            value: _ttsEnabled,
            onChanged: (v) async {
              setState(() => _ttsEnabled = v);
              await TtsService.instance.setEnabled(v);
            },
          ),
          _actionTile(
            icon: Icons.translate,
            title: 'Assistant language',
            subtitle: _assistantLanguage.displayName,
            onTap: () => _showLanguageSelector(),
          ),
          _toggleTile(
            icon: Icons.auto_awesome,
            title: 'RAG Memory',
            subtitle: 'Remember conversations for contextual answers',
            value: _ragMemory,
            onChanged: (v) {
              setState(() => _ragMemory = v);
              _saveSetting('settings_rag_memory', v);
            },
          ),
          _toggleTile(
            icon: Icons.battery_charging_full_outlined,
            title: 'Battery optimization',
            subtitle: 'Release model after 5 minutes idle to save power',
            value: _batteryOptimization,
            onChanged: (v) {
              setState(() => _batteryOptimization = v);
              _saveSetting('settings_battery_optimization', v);
              ModelOrchestrator.instance.setBatteryOptimization(v);
            },
          ),
          _toggleTile(
            icon: Icons.bug_report,
            title: 'Debug mode',
            subtitle: 'Enable verbose logging for troubleshooting',
            value: _debugMode,
            onChanged: (v) {
              setState(() => _debugMode = v);
              _saveSetting('settings_debug_mode', v);
              ModelOrchestrator.instance.setDebugMode(v);
            },
          ),
          if (_debugMode) ...[
            _actionTile(
              icon: Icons.restart_alt,
              title: 'Reset inference engine',
              subtitle: 'Unload model and clear GPU memory if stuck',
              onTap: _confirmResetInference,
            ),
            ListTile(
              leading: const Icon(Icons.memory, color: Colors.white70),
              title: const Text(
                'Process memory',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _debugMemoryLabel,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              onTap: _refreshDebugMemory,
            ),
          ],
          _actionTile(
            icon: Icons.psychology,
            title: 'Memory overview',
            subtitle: 'What Nova knows about you — view, ask, edit',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const UserMemoryOverviewScreen(),
                ),
              );
            },
          ),
          _actionTile(
            icon: Icons.bookmark_border,
            title: 'Custom Memories',
            subtitle: 'Manually manage saved entries',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const MemoryManagementScreen(),
                ),
              );
            },
          ),
          _actionTile(
            icon: Icons.menu_book_outlined,
            title: 'Knowledge Base',
            subtitle: 'Ingest PDFs and docs for RAG context',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const KnowledgeBaseScreen(),
                ),
              );
            },
          ),
          _actionTile(
            icon: Icons.face,
            title: 'Agent Identity',
            subtitle: 'Customize name, avatar, skills & sources',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const IdentityConfigScreen(),
                ),
              );
            },
          ),
          _actionTile(
            icon: Icons.task_alt,
            title: 'Tasks',
            subtitle: 'View and manage your tasks',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
              );
            },
          ),
          _actionTile(
            icon: Icons.note_alt_outlined,
            title: 'Notes',
            subtitle: 'View and manage your notes',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const NotesScreen()),
              );
            },
          ),
          _actionTile(
            icon: Icons.build_outlined,
            title: 'External Tools & Data',
            subtitle: 'MCP integrations, HTTP tools, data sources',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const McpSettingsScreen(),
                ),
              );
            },
          ),
          _actionTile(
            icon: Icons.person_outline,
            title: 'Assistant Role',
            subtitle: _assistantRole.displayName,
            onTap: () => _showRoleSelector(),
          ),
          _actionTile(
            icon: Icons.assistant_outlined,
            title: 'Default assistant',
            subtitle: _isAssistantRoleHeld
                ? 'Nova is your default assistant'
                : 'Tap to set Nova as system assistant',
            onTap: () async {
              await AssistantRoleService.instance.requestAssistantRole();
            },
          ),
          const SizedBox(height: 24),

          _sectionHeader('About'),
          _infoTile(
            icon: Icons.info_outline,
            title: 'Nova Assistant',
            subtitle: 'Version $_appVersion — Powered by Gemma',
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
            icon: Icons.upload_file_outlined,
            title: 'Export settings',
            subtitle: 'Share preferences as JSON (no models)',
            onTap: () async {
              await SettingsBackupService.instance.shareExport();
            },
          ),
          _actionTile(
            icon: Icons.download_outlined,
            title: 'Import settings',
            subtitle: 'Restore preferences from JSON backup',
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  title: const Text(
                    'Import settings?',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: Text(
                    'This replaces your current settings. '
                    'Models and OAuth tokens are not imported.',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Import'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;

              final result = await SettingsBackupService.instance
                  .importFromPicker();
              if (!context.mounted) return;
              if (result.cancelled) return;
              if (result.success) {
                await _loadSettings();
                await ModelOrchestrator.refreshSettings();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings imported')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.error ?? 'Import failed'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
          ),
          _actionTile(
            icon: Icons.lightbulb_outline,
            title: 'Prompt presets',
            subtitle: 'Manage reusable prompt templates',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const PromptPresetsScreen(),
                ),
              );
            },
          ),
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
            icon: Icons.search_outlined,
            title: 'Search conversation history',
            subtitle: 'Find past messages by keyword',
            onTap: () async {
              final result = await Navigator.push<ChatMessage>(
                context,
                MaterialPageRoute<ChatMessage>(
                  builder: (_) => const ConversationSearchScreen(),
                ),
              );
              if (result != null && context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AssistantScreen(),
                  ),
                );
              }
            },
          ),
          _actionTile(
            icon: Icons.refresh,
            title: 'Reload models',
            subtitle: 'Refresh installed model list',
            onTap: () async {
              setState(() => _installStatus = 'Reloading models...');
              await ModelManager.instance.initialize();
              if (mounted) {
                setState(() => _installStatus = '');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Model list refreshed'),
                    backgroundColor: Color(0xFF6C63FF),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndInstallModel(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'task', 'gguf'],
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

      // Auto-detect fileType from extension
      final ext = file.name.split('.').last.toLowerCase();
      final fileType = switch (ext) {
        'litertlm' => ModelFileType.litertlm,
        'task' => ModelFileType.task,
        _ => ModelFileType.task,
      };

      // Show model type picker
      if (!context.mounted) return;
      final modelType = await _showModelTypePicker(context);
      if (modelType == null) return;

      // Install
      setState(() => _installStatus = 'Installing ${file.name}...');
      final installed = await ModelManager.instance.installFromFile(
        filePath: file.path!,
        modelType: modelType,
        fileType: fileType,
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

  Future<void> _showLanguageSelector() async {
    final selected = await showModalBottomSheet<AssistantLanguage>(
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
                'Assistant language',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...AssistantLanguage.values.map(
              (lang) => ListTile(
                title: Text(
                  lang.displayName,
                  style: TextStyle(
                    color: _assistantLanguage == lang
                        ? const Color(0xFF6C63FF)
                        : Colors.white,
                    fontWeight: _assistantLanguage == lang
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  lang.subtitle,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                trailing: _assistantLanguage == lang
                    ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                    : null,
                onTap: () => Navigator.pop(ctx, lang),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (selected != null && selected != _assistantLanguage) {
      setState(() => _assistantLanguage = selected);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AssistantLanguage.prefsKey, selected.prefsValue);
    }
  }

  Future<void> _showRoleSelector() async {
    final selected = await showModalBottomSheet<AssistantRole>(
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
                'Assistant Role',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...AssistantRole.values.map(
              (role) => ListTile(
                leading: Icon(
                  _roleIcon(role),
                  color: _assistantRole == role
                      ? const Color(0xFF6C63FF)
                      : Colors.grey[400],
                ),
                title: Text(
                  role.displayName,
                  style: TextStyle(
                    color: _assistantRole == role
                        ? const Color(0xFF6C63FF)
                        : Colors.white,
                    fontWeight: _assistantRole == role
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                trailing: _assistantRole == role
                    ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                    : null,
                onTap: () => Navigator.pop(ctx, role),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (selected != null && selected != _assistantRole) {
      setState(() => _assistantRole = selected);
      await _saveAssistantRole(selected);
    }
  }

  Future<void> _showModeSwitchDialog(
    BuildContext context,
    UserMode targetMode,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          targetMode == UserMode.beginner
              ? 'Switch to Beginner Mode?'
              : 'Switch to Expert Mode?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          targetMode == UserMode.beginner
              ? 'You\'ll see a simplified UI with only the basics. '
                    'You can switch back to Expert Mode anytime from Settings.'
              : 'You\'ll have access to all features including screenshots, '
                    'file attachments, and advanced settings.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
            ),
            child: const Text('Switch Mode'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await UserPreferencesService.instance.setMode(targetMode);
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/app', (_) => false);
      }
    }
  }

  IconData _roleIcon(AssistantRole role) {
    return switch (role) {
      AssistantRole.helpful => Icons.help_outline,
      AssistantRole.coder => Icons.code,
      AssistantRole.creative => Icons.palette_outlined,
      AssistantRole.student => Icons.school_outlined,
      AssistantRole.analyst => Icons.analytics_outlined,
    };
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
      ModelHuggingFaceURLs.fileNameFor(model),
    );

    return GestureDetector(
      onTap: installed ? null : () => _downloadModel(context, model),
      child: Container(
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
                    installed ? 'Installed' : 'Tap to install',
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
      ),
    );
  }

  Future<void> _downloadModel(BuildContext context, NovaModel model) async {
    final url = ModelHuggingFaceURLs.urlFor(model);
    setState(() => _installStatus = 'Downloading ${model.displayName}...');

    // #region agent log
    await AgentDebugLog.log(
      hypothesisId: 'H3-H4',
      location: 'settings_screen.dart:_downloadModel:start',
      message: 'Settings download tapped',
      data: {
        'model': model.name,
        'url': url,
        'expectedFile': ModelHuggingFaceURLs.fileNameFor(model),
      },
    );
    // #endregion

    try {
      final installed = await ModelManager.instance.installFromNetwork(
        url: url,
        modelType: model.modelType,
        fileType: model.fileType,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _installStatus = 'Downloading: $progress%');
          }
        },
      );

      // #region agent log
      final expected = ModelHuggingFaceURLs.fileNameFor(model);
      await AgentDebugLog.log(
        hypothesisId: 'H3-H4',
        location: 'settings_screen.dart:_downloadModel:result',
        message: 'Settings download finished',
        data: {
          'model': model.name,
          'success': installed != null,
          'fileName': installed?.fileName,
          'prefsHasExpected': ModelManager.instance.isModelInstalled(expected),
          'diskHasExpected': await ModelManager.instance.isInstalledOnDisk(
            expected,
          ),
        },
      );
      // #endregion

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
              content: Text('Failed to download model'),
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

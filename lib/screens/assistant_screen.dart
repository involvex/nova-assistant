import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nova_assistant/models/attached_data.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/platform/screenshot_service.dart';
import 'package:nova_assistant/tools/tool_definitions.dart';
import 'package:nova_assistant/widgets/chat_bubble.dart';
import 'package:nova_assistant/widgets/voice_input.dart';
import 'package:nova_assistant/screens/settings_screen.dart';
import 'package:nova_assistant/screens/model_selector_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with WidgetsBindingObserver {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _isGenerating = false;
  bool _thinkingMode = false;
  bool _offlineMode = false;
  Uint8List? _currentScreenshot;
  bool _isLoadingInitialScreenshot =
      true; // Track if initial screenshot is loading
  String _status = 'Ready';
  bool _shouldPreserveScreenshot = false;
  final AttachmentManager _attachmentManager = AttachmentManager.instance;
  StreamSubscription<void>? _historyClearedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThinkingMode();
    _loadInitialScreenshot();
    _loadHistory();
    _requestPermissions();
    _inputController.addListener(() => setState(() {}));
    _listenToModelStatus();
    _checkModelAvailability();
    _historyClearedSub =
        ModelOrchestrator.instance.historyClearedStream.listen((_) {
      if (mounted) {
        setState(() => _messages.clear());
      }
    });
  }

  Future<void> _loadHistory() async {
    final history = await ChatHistoryService.load();
    if (mounted && history.isNotEmpty) {
      setState(() => _messages.addAll(history));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _loadThinkingMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _thinkingMode = prefs.getBool('settings_thinking_mode') ?? false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.microphone, Permission.photos].request();
  }

  void _listenToModelStatus() {
    ModelOrchestrator.instance.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
      _checkModelAvailability();
      if (status.startsWith('NEED_DOWNLOAD_CONSENT:')) {
        final modelName = status.substring('NEED_DOWNLOAD_CONSENT:'.length);
        _showDownloadConsentDialog(modelName);
      }
    });
  }

  Future<void> _checkModelAvailability() async {
    final manager = ModelManager.instance;
    bool anyInstalled = false;
    for (final model in NovaModel.values) {
      final fileName = ModelHuggingFaceURLs.fileNameFor(model);
      if (await manager.isInstalledOnDisk(fileName)) {
        anyInstalled = true;
        break;
      }
    }
    if (mounted) {
      setState(() => _offlineMode = !anyInstalled);
    }
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF6B6B).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 18,
            color: Color(0xFFFF6B6B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No AI model installed. Go to Settings > AI Models to download one.',
              style: TextStyle(color: Colors.grey[300], fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            child: const Text(
              'Install',
              style: TextStyle(
                color: Color(0xFFFF6B6B),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDownloadConsentDialog(String modelName) async {
    final orchestrator = ModelOrchestrator.instance;
    final model = orchestrator.downloadConsentModel;
    final url = orchestrator.downloadConsentUrl;
    if (model == null || url == null) return;

    final choice = await showDialog<DownloadConsent>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Download $modelName?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This model is not installed on your device.',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 8),
            Text(
              'Size: ~${model.sizeMB}MB',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Source: ${Uri.parse(url).host}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, DownloadConsent.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, DownloadConsent.pickFile),
            child: const Text('Pick File'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, DownloadConsent.download),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    orchestrator.completeDownloadConsent(choice ?? DownloadConsent.cancel);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyClearedSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ModelOrchestrator.instance.releaseIdleResources();
    } else if (state == AppLifecycleState.resumed) {
      _checkModelAvailability();
    }
  }

  Future<void> _loadInitialScreenshot() async {
    _isLoadingInitialScreenshot = true;
    try {
      final screenshot = await ScreenshotService.instance.getLatestScreenshot();
      if (mounted) {
        setState(() {
          _currentScreenshot = screenshot;
          _isLoadingInitialScreenshot = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitialScreenshot = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _retryFromError(int errorIndex) {
    // Find the user message that preceded this error
    String? userText;
    for (var i = errorIndex - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        userText = _messages[i].text;
        break;
      }
    }
    if (userText == null || userText.isEmpty) return;

    // Remove the error message and any following messages
    setState(() {
      _messages.removeRange(errorIndex, _messages.length);
    });

    // Re-send
    _inputController.text = userText;
    _sendMessage();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    // Wait for initial screenshot to load if still loading (from assistant mode)
    // This ensures screenshot is captured before model selection happens
    if (_isLoadingInitialScreenshot && _currentScreenshot == null) {
      debugPrint('Waiting for initial screenshot to load...');
      while (_isLoadingInitialScreenshot && _currentScreenshot == null) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      debugPrint('Screenshot loaded: ${_currentScreenshot != null}');
    }

    _inputController.clear();
    _inputFocus.unfocus();

    // Add user message
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      imageData: _currentScreenshot,
    );

    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
    });

    ChatHistoryService.save(_messages); // Persist immediately

    _scrollToBottom();

    // Add placeholder assistant message
    final assistantId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    final assistantMsg = ChatMessage(
      id: assistantId,
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      modelName: null,
      isStreaming: true,
    );

    setState(() => _messages.add(assistantMsg));

    try {
      String accumulated = '';

      await for (final result in ModelOrchestrator.instance.processMessage(
        query: text,
        screenshot: _currentScreenshot,
        thinkingMode: _thinkingMode,
        tools: NovaTools.all,
        attachments: _attachmentManager.attachments,
        // Always force heavy model in assistant mode for reliability
        forcePrimaryModel: true,
      )) {
        if (!mounted) break;

        accumulated = result.text;

        final idx = _messages.indexWhere((m) => m.id == assistantId);
        if (idx != -1) {
          setState(() {
            _messages[idx] = _messages[idx].copyWith(
              text: accumulated,
              modelName: result.model.displayName,
              isStreaming: result.isStreaming,
              isError: false,
              toolCalls: result.toolCalls != null
                  ? jsonEncode(result.toolCalls)
                  : null,
              thinking: result.thinking,
              inferenceTimeMs:
                  result.inferenceTimeMs ?? _messages[idx].inferenceTimeMs,
            );
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == assistantId);
      if (e is ModelNeedsFilePickException) {
        _shouldPreserveScreenshot = true;
        setState(() {
          _isGenerating = false;
        });
        _attachmentManager.clear();
        await _handleModelFilePick(e.model);
        _inputController.text = text;
        return;
      }
      if (idx != -1) {
        String errorText;
        if (e is ModelException) {
          errorText = '⚠️ ${e.message}\n\n${e.suggestion ?? ''}';
        } else {
          errorText = 'Sorry, I encountered an error: $e';
        }
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            text: errorText,
            isStreaming: false,
            isError: true,
          );
        });
      }
    } finally {
      setState(() {
        _isGenerating = false;
        if (!_shouldPreserveScreenshot) {
          _currentScreenshot = null;
        }
        _shouldPreserveScreenshot = false;
      });
      _attachmentManager.clear();
    }
  }

  Future<void> _captureAndAttachScreenshot() async {
    final granted = await ScreenshotService.instance.requestCapture();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Screen capture denied. Enable in Settings.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final screenshot = await ScreenshotService.instance.getLatestScreenshot();
    if (screenshot != null && mounted) {
      setState(() => _currentScreenshot = screenshot);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screenshot attached!'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF6C63FF),
        ),
      );
    }
  }

  Future<void> _showModelSelectorSheet(BuildContext context) async {
    final isAutoMode = ModelOrchestrator.instance.preferredModelType == null;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ModelSelectorSheet(
        currentSelection: ModelOrchestrator.instance.preferredModelType,
        isAutoMode: isAutoMode,
        onModelSelected: (model) {
          ModelOrchestrator.instance.preferredModelType = model;
          setState(() {});
        },
        onAutoModeChanged: (auto) {
          if (auto) {
            ModelOrchestrator.instance.clearModelOverride();
          }
          setState(() {});
        },
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    final status = await Permission.photos.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.isPermanentlyDenied
                  ? 'Photo access denied. Enable it in Settings.'
                  : 'Photo access is required to attach images.',
            ),
            backgroundColor: Colors.red,
            action: status.isPermanentlyDenied
                ? SnackBarAction(
                    label: 'Settings',
                    onPressed: () => openAppSettings(),
                  )
                : null,
          ),
        );
      }
      return;
    }

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        if (mounted) {
          setState(() => _currentScreenshot = bytes);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image attached!'),
              duration: Duration(seconds: 1),
              backgroundColor: Color(0xFF6C63FF),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.path == null) continue;

        final attachment = AttachedData(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: file.name,
          type: AttachedDataType.file,
          filePath: file.path,
          attachedAt: DateTime.now(),
          fileSizeBytes: file.size,
        );

        _attachmentManager.add(attachment);
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.files.length} file(s) attached'),
            duration: const Duration(seconds: 1),
            backgroundColor: const Color(0xFF6C63FF),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleModelFilePick(NovaModel model) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'task', 'gguf'],
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Installing ${model.displayName}...'),
          backgroundColor: const Color(0xFF6C63FF),
        ),
      );

      final installed = await ModelManager.instance.installFromFile(
        filePath: file.path!,
        modelType: model.modelType,
        fileType: model.fileType,
      );

      if (installed != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${model.displayName} installed!'),
            backgroundColor: Colors.green,
          ),
        );

        ModelOrchestrator.instance.refreshModelOverride();
        if (_messages.isNotEmpty) {
          final lastUserMsg = _messages.lastWhere(
            (m) => m.isUser,
            orElse: () => _messages.first,
          );
          _inputController.text = lastUserMsg.text;
          if (lastUserMsg.imageData != null) {
            _currentScreenshot = lastUserMsg.imageData;
          }
          _sendMessage();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to install model: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUrlDialog() {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Attach URL', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'https://example.com',
                hintStyle: TextStyle(color: Colors.grey[600]),
                labelText: 'URL',
                labelStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[700]!),
                ),
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Optional label',
                hintStyle: TextStyle(color: Colors.grey[600]),
                labelText: 'Name (optional)',
                labelStyle: TextStyle(color: Colors.grey[400]),
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
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty) return;

              final name = nameController.text.trim().isEmpty
                  ? Uri.tryParse(url)?.host ?? url
                  : nameController.text.trim();

              final attachment = AttachedData(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: name,
                type: AttachedDataType.url,
                url: url,
                attachedAt: DateTime.now(),
              );

              _attachmentManager.add(attachment);
              Navigator.pop(ctx);
              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('URL attached!'),
                  duration: Duration(seconds: 1),
                  backgroundColor: Color(0xFF6C63FF),
                ),
              );
            },
            child: const Text(
              'Attach',
              style: TextStyle(color: Color(0xFF6C63FF)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            _buildAppBar(),

            // Screenshot and attachment indicators
            if (_currentScreenshot != null) _buildScreenshotIndicator(),
            if (_attachmentManager.hasAttachments) _buildAttachmentIndicator(),

            // Offline indicator
            if (_offlineMode) _buildOfflineBanner(),

            // Messages
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return ChatBubble(
                          message: msg,
                          onScreenshotTap: msg.imageData != null
                              ? () => _showFullScreenshot(msg.imageData!)
                              : null,
                          onRetry: msg.isError && !msg.isUser
                              ? () => _retryFromError(index)
                              : null,
                          onSettingsTap: msg.isError && !msg.isUser
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (context) =>
                                          const SettingsScreen(),
                                    ),
                                  );
                                }
                              : null,
                          onCopy: () {
                            Clipboard.setData(ClipboardData(text: msg.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          onReactionRequest: () => _showReactionPicker(index),
                          onReactionChipTap: (emoji) =>
                              _toggleReaction(index, emoji),
                        );
                      },
                    ),
            ),

            // Status bar
            _buildStatusBar(),

            // Input bar
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          // Nova logo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text(
                'N',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Thinking mode toggle
          Tooltip(
            message: 'Thinking mode (show reasoning)',
            child: IconButton(
              onPressed: () async {
                setState(() => _thinkingMode = !_thinkingMode);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('settings_thinking_mode', _thinkingMode);
              },
              icon: Icon(
                Icons.psychology_outlined,
                color: _thinkingMode ? const Color(0xFF6C63FF) : Colors.grey,
              ),
            ),
          ),

          // Model picker - opens bottom sheet
          Tooltip(
            message: 'Select model',
            child: GestureDetector(
              onTap: () => _showModelSelectorSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ModelOrchestrator.instance.preferredModelType == null
                          ? Icons.auto_awesome
                          : Icons.account_tree,
                      size: 16,
                      color: const Color(0xFF6C63FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ModelOrchestrator
                              .instance.preferredModelType?.displayName ??
                          'Auto',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),

          // Screenshot capture
          Tooltip(
            message: 'Capture screen',
            child: IconButton(
              onPressed: _captureAndAttachScreenshot,
              icon: const Icon(
                Icons.screenshot_monitor_outlined,
                color: Colors.grey,
              ),
            ),
          ),

          // Conversation export
          PopupMenuButton<String>(
            tooltip: 'Export conversation',
            onSelected: (format) async {
              String? path;
              if (format == 'text') {
                path = await ChatHistoryService.exportAsText();
              } else {
                path = await ChatHistoryService.exportAsJson();
              }
              if (path != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Exported to:\n$path'),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'text',
                child: Text('Export as Text'),
              ),
              const PopupMenuItem<String>(
                value: 'json',
                child: Text('Export as JSON'),
              ),
            ],
            child: const Tooltip(
              message: 'Export conversation',
              child: Icon(Icons.download_outlined, color: Colors.grey),
            ),
          ),

          // Settings
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 14, color: Color(0xFF6C63FF)),
          const SizedBox(width: 6),
          const Text(
            'Screen attached',
            style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _currentScreenshot = null),
            child: const Icon(Icons.close, size: 14, color: Color(0xFF6C63FF)),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentIndicator() {
    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachmentManager.attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final att = _attachmentManager.attachments[index];
          return _buildAttachmentChip(att);
        },
      ),
    );
  }

  Widget _buildAttachmentChip(AttachedData att) {
    final iconData = _getIconForAttachment(att);
    final color = _getColorForAttachment(att);
    final displayText = _getDisplayName(att);
    final subtitle = _getSubtitle(att);

    return Tooltip(
      message: _getTooltip(att),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(iconData, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayText,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                setState(() => _attachmentManager.remove(att.id));
              },
              child: Icon(
                Icons.close,
                size: 14,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForAttachment(AttachedData att) {
    if (att.type == AttachedDataType.url) return Icons.link;
    if (att.type == AttachedDataType.text) return Icons.text_snippet_outlined;

    final name = att.name.toLowerCase();
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.json')) return Icons.code_outlined;
    if (name.endsWith('.dart') ||
        name.endsWith('.py') ||
        name.endsWith('.js')) {
      return Icons.code_outlined;
    }
    if (name.endsWith('.md') || name.endsWith('.txt')) {
      return Icons.description_outlined;
    }
    if (name.endsWith('.csv') || name.endsWith('.xlsx')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _getColorForAttachment(AttachedData att) {
    if (att.type == AttachedDataType.url) return const Color(0xFF00BFA5);
    if (att.type == AttachedDataType.text) return const Color(0xFFFF9100);

    final name = att.name.toLowerCase();
    if (name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp')) {
      return const Color(0xFFE040FB);
    }
    if (name.endsWith('.pdf')) return const Color(0xFFFF5252);
    if (name.endsWith('.json') ||
        name.endsWith('.dart') ||
        name.endsWith('.py') ||
        name.endsWith('.js')) {
      return const Color(0xFF448AFF);
    }
    return const Color(0xFF6C63FF);
  }

  String _getDisplayName(AttachedData att) {
    if (att.type == AttachedDataType.url) {
      try {
        final uri = Uri.parse(att.url ?? '');
        return uri.host;
      } catch (_) {
        return att.name;
      }
    }
    // Truncate long filenames
    if (att.name.length > 16) {
      return '${att.name.substring(0, 13)}...';
    }
    return att.name;
  }

  String? _getSubtitle(AttachedData att) {
    if (att.type == AttachedDataType.url) {
      try {
        final uri = Uri.parse(att.url ?? '');
        final path = uri.path;
        if (path.length > 20) return '${path.substring(0, 17)}...';
        return path.isEmpty ? null : path;
      } catch (_) {
        return null;
      }
    }
    if (att.type == AttachedDataType.file) {
      if (att.fileSizeBytes != null) {
        if (att.fileSizeBytes! > 1024 * 1024) {
          return '${(att.fileSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
        }
        if (att.fileSizeBytes! > 1024) {
          return '${(att.fileSizeBytes! / 1024).toStringAsFixed(1)} KB';
        }
        return '${att.fileSizeBytes} B';
      }
    }
    return null;
  }

  String _getTooltip(AttachedData att) {
    final buffer = StringBuffer(att.name);
    if (att.type == AttachedDataType.url) {
      buffer.writeln('\nURL: ${att.url}');
    }
    return buffer.toString();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Hi, I\'m Nova',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your on-device AI assistant, powered by Gemma.\n'
            'Tap the mic or type to start.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], height: 1.5),
          ),
          const SizedBox(height: 32),
          // Quick suggestion chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _quickChip('What\'s on my screen?'),
              _quickChip('Set an alarm for 7 AM'),
              _quickChip('Summarize this page'),
              _quickChip('Open Settings'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickChip(String label) {
    return GestureDetector(
      onTap: () {
        _inputController.text = label;
        _sendMessage();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isGenerating ? Colors.orange : Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _status,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const Spacer(),
          if (_thinkingMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology, size: 10, color: Color(0xFF6C63FF)),
                  SizedBox(width: 4),
                  Text(
                    'Thinking',
                    style: TextStyle(fontSize: 10, color: Color(0xFF6C63FF)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Attachment buttons row
          Row(
            children: [
              IconButton(
                onPressed: _captureAndAttachScreenshot,
                icon: const Icon(
                  Icons.screenshot_monitor_outlined,
                  color: Colors.grey,
                ),
                tooltip: 'Attach screenshot',
              ),
              IconButton(
                onPressed: _pickImageFromGallery,
                icon: const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.grey,
                ),
                tooltip: 'Attach from gallery',
              ),
              IconButton(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file, color: Colors.grey),
                tooltip: 'Attach file',
              ),
              IconButton(
                onPressed: _showUrlDialog,
                icon: const Icon(Icons.link, color: Colors.grey),
                tooltip: 'Attach URL',
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Text input + voice + send row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Ask Nova anything...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              VoiceInputButton(
                onTranscription: (text) {
                  if (text.isNotEmpty) {
                    _inputController.text = text;
                    _sendMessage();
                  }
                },
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  onPressed:
                      _inputController.text.trim().isNotEmpty && !_isGenerating
                          ? _sendMessage
                          : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: _inputController.text.trim().isNotEmpty
                        ? const Color(0xFF6C63FF)
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _reactionEmojis = ['👍', '👎', '😄', '❤️', '🤔'];

  Future<void> _showReactionPicker(int messageIndex) async {
    final msg = _messages[messageIndex];
    final items = <Widget>[];

    if (msg.isUser) {
      items.add(
        ListTile(
          leading: const Icon(Icons.copy, color: Colors.white70, size: 20),
          title: const Text('Copy', style: TextStyle(color: Colors.white)),
          onTap: () {
            Navigator.pop(context);
            Clipboard.setData(ClipboardData(text: msg.text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      );
      items.add(const Divider(color: Colors.white10, height: 1));
    }

    items.addAll(
      _reactionEmojis.map((emoji) {
        final count = msg.reactions[emoji] ?? 0;
        return ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 22)),
          title: Text(
            count > 0 ? '$emoji ($count)' : emoji,
            style: TextStyle(color: Colors.grey[300]),
          ),
          onTap: () {
            Navigator.pop(context);
            _toggleReaction(messageIndex, emoji);
          },
        );
      }),
    );

    await showModalBottomSheet<void>(
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
                'Add Reaction',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...items,
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _toggleReaction(int messageIndex, String emoji) {
    setState(() {
      final msg = _messages[messageIndex];
      final newReactions = Map<String, int>.from(msg.reactions);
      final current = newReactions[emoji] ?? 0;
      if (current > 0) {
        newReactions[emoji] = current - 1;
        if (newReactions[emoji] == 0) {
          newReactions.remove(emoji);
        }
      } else {
        newReactions[emoji] = 1;
      }
      _messages[messageIndex] = msg.copyWith(reactions: newReactions);
    });
    ChatHistoryService.save(_messages);
  }

  void _showFullScreenshot(Uint8List data) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(data),
            ),
          ),
        ),
      ),
    );
  }
}

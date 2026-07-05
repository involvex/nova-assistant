import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/platform/screenshot_service.dart';
import 'package:nova_assistant/tools/tool_definitions.dart';
import 'package:nova_assistant/widgets/chat_bubble.dart';
import 'package:nova_assistant/widgets/voice_input.dart';
import 'package:nova_assistant/screens/settings_screen.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _isGenerating = false;
  bool _thinkingMode = false;
  Uint8List? _currentScreenshot;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _loadInitialScreenshot();
    _inputController.addListener(() => setState(() {}));
    _listenToModelStatus();
  }

  void _listenToModelStatus() {
    ModelOrchestrator.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() => _status = status);
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadInitialScreenshot() async {
    final screenshot = await ScreenshotService.instance.getLatestScreenshot();
    if (screenshot != null && mounted) {
      setState(() => _currentScreenshot = screenshot);
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

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

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
            );
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == assistantId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            text: 'Sorry, I encountered an error: $e',
            isStreaming: false,
            isError: true,
          );
        });
      }
    } finally {
      setState(() => _isGenerating = false);
      _currentScreenshot = null; // Clear screenshot after use
    }
  }

  Future<void> _captureAndAttachScreenshot() async {
    await ScreenshotService.instance.requestCapture();
    await Future<void>.delayed(const Duration(milliseconds: 800));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            _buildAppBar(),

            // Screenshot indicator
            if (_currentScreenshot != null) _buildScreenshotIndicator(),

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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nova',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'On-device AI Assistant',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          // Thinking mode toggle
          Tooltip(
            message: 'Thinking mode (show reasoning)',
            child: IconButton(
              onPressed: () => setState(() => _thinkingMode = !_thinkingMode),
              icon: Icon(
                Icons.psychology_outlined,
                color: _thinkingMode ? const Color(0xFF6C63FF) : Colors.grey,
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
      child: Row(
        children: [
          // Screenshot attach button
          if (_currentScreenshot == null)
            IconButton(
              onPressed: _captureAndAttachScreenshot,
              icon: const Icon(
                Icons.add_photo_alternate_outlined,
                color: Colors.grey,
              ),
              tooltip: 'Attach screenshot',
            ),

          // Text input
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

          // Voice input
          VoiceInputButton(
            isRecording: false,
            onAudioRecorded: (path) {
              // Audio recording → transcription → send
            },
          ),

          const SizedBox(width: 8),

          // Send button
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
    );
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

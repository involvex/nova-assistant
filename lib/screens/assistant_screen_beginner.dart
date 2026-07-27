import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:nova_assistant/tools/tool_definitions.dart';
import 'package:nova_assistant/widgets/chat_bubble.dart';
import 'package:nova_assistant/widgets/voice_input.dart';

class AssistantScreenBeginner extends StatefulWidget {
  const AssistantScreenBeginner({super.key});

  @override
  State<AssistantScreenBeginner> createState() =>
      _AssistantScreenBeginnerState();
}

class _AssistantScreenBeginnerState extends State<AssistantScreenBeginner> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _isGenerating = false;
  String _status = 'Ready';
  String _userName = '';
  StreamSubscription<void>? _historyClearedSub;
  StreamSubscription<String>? _statusSub;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadHistory();
    _requestPermissions();
    _inputController.addListener(() => setState(() {}));
    _listenToModelStatus();
    _historyClearedSub = ModelOrchestrator.instance.historyClearedStream.listen(
      (_) {
        if (mounted) {
          setState(() => _messages.clear());
        }
      },
    );
  }

  Future<void> _loadUserName() async {
    final name = await UserPreferencesService.instance.getUserName();
    if (mounted) {
      setState(() => _userName = name);
    }
  }

  Future<void> _loadHistory() async {
    final history = await ChatHistoryService.load();
    if (mounted && history.isNotEmpty) {
      setState(() => _messages.addAll(history));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.microphone].request();
  }

  void _listenToModelStatus() {
    _statusSub?.cancel();
    _statusSub = ModelOrchestrator.instance.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });
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

    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isGenerating = true;
    });

    ChatHistoryService.save(_messages);

    _scrollToBottom();

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
        screenshot: null,
        thinkingMode: false,
        tools: NovaTools.all,
        attachments: [],
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
      if (idx != -1) {
        String errorText;
        errorText = e is ModelException
            ? '⚠️ ${e.message}\n\n${e.suggestion ?? ''}'
            : 'Sorry, I encountered an error: $e';
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            text: errorText,
            isStreaming: false,
            isError: true,
          );
        });
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _regenerateResponse(int assistantIndex) {
    // Find the user message that preceded this assistant response
    String? userText;
    for (var i = assistantIndex - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        userText = _messages[i].text;
        break;
      }
    }
    if (userText == null || userText.isEmpty) return;

    // Remove the assistant message and any following messages
    setState(() {
      _messages.removeRange(assistantIndex, _messages.length);
    });
    ModelOrchestrator.instance.invalidateSessionForReplay(
      List<ChatMessage>.from(_messages.where((m) => !m.isStreaming)),
    );

    // Re-send the user message
    _inputController.text = userText;
    _sendMessage();
  }

  Future<void> _switchToExpertMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Switch to Expert Mode?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'You\'ll have access to all features including screenshots, '
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
      final navigator = Navigator.of(context);
      await UserPreferencesService.instance.setMode(UserMode.expert);
      if (mounted) {
        navigator.pushReplacementNamed('/app');
      }
    }
  }

  @override
  void dispose() {
    _historyClearedSub?.cancel();
    _statusSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageList(),
            ),
            _buildStatusBar(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'N',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName.isNotEmpty ? 'Hi $_userName!' : 'Nova',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Tap the mic and ask me anything',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _switchToExpertMode,
            icon: Icon(Icons.settings_outlined, color: Colors.grey[400]),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _userName.isNotEmpty
                ? 'Hey $_userName, what can I help with?'
                : 'What can I help you with?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _quickChip('Set an alarm for 7:00 PM'),
              _quickChip('What time is it?'),
              _quickChip('Call mom'),
              _quickChip('Remind me to drink water'),
              _quickChip('Open Settings'),
              _quickChip('Tell me a joke'),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];

        return ChatBubble(
          message: msg,
          onCopy: () {
            final attribution = msg.isUser
                ? ''
                : '\n\n— ${msg.modelName ?? "Nova"} · ${_formatTimestamp(msg.timestamp)}';
            Clipboard.setData(ClipboardData(text: '${msg.text}$attribution'));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          onRegenerate: !msg.isUser && !msg.isError && !msg.isStreaming
              ? () => _regenerateResponse(index)
              : null,
        );
      },
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
          const SizedBox(width: 12),
          VoiceInputButton(
            onPartial: (partial) {
              _inputController.text = partial;
              _inputController.selection = TextSelection.collapsed(
                offset: partial.length,
              );
            },
            onTranscription: (text) {
              if (text.isEmpty) return;
              _inputController.text = text;
              if (_isGenerating || ModelOrchestrator.instance.isBusy) {
                return;
              }
              _sendMessage();
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _inputController.text.trim().isNotEmpty && !_isGenerating
                ? _sendMessage
                : null,
            icon: Icon(
              Icons.send_rounded,
              color: _inputController.text.trim().isNotEmpty
                  ? const Color(0xFF6C63FF)
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
  }
}

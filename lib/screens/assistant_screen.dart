import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nova_assistant/models/attached_data.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/chat_bubble_theme.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/document_extractor.dart';
import 'package:nova_assistant/services/audio_recorder_service.dart';
import 'package:nova_assistant/services/chat_history_service.dart';
import 'package:nova_assistant/services/conversation_summary_service.dart';
import 'package:nova_assistant/services/export_service.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_release_policy.dart';
import 'package:nova_assistant/services/tts_service.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/services/mcp_service.dart';
import 'package:nova_assistant/platform/screenshot_service.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/tools/tool_definitions.dart';
import 'package:nova_assistant/widgets/chat_bubble.dart';
import 'package:nova_assistant/widgets/in_chat_search_bar.dart';
import 'package:nova_assistant/widgets/voice_input.dart';
import 'package:nova_assistant/screens/chat_history_screen.dart';
import 'package:nova_assistant/screens/settings_screen.dart';
import 'package:nova_assistant/screens/model_selector_sheet.dart';
import 'package:nova_assistant/screens/custom_model_import_sheet.dart';
import 'package:nova_assistant/services/follow_up_suggestion_service.dart';
import 'package:nova_assistant/services/memory_diagnostics_service.dart';
import 'package:nova_assistant/services/platform_adaptation_service.dart';
import 'package:nova_assistant/services/prompt_presets_service.dart';
import 'package:nova_assistant/services/shizuku_service.dart';
import 'package:nova_assistant/utils/agent_debug_log.dart';
import 'package:nova_assistant/utils/message_limits.dart';
import 'package:nova_assistant/widgets/suggestion_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AssistantScreen extends StatefulWidget {
  final String? conversationId;
  final String? initialPrompt;
  final bool autoSendInitialPrompt;
  final bool isSystemAssistantLaunch;

  const AssistantScreen({
    super.key,
    this.conversationId,
    this.initialPrompt,
    this.autoSendInitialPrompt = true,
    this.isSystemAssistantLaunch = false,
  });

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
  bool _isLoadingInitialScreenshot = true;
  String _status = 'Ready';
  bool _shouldPreserveScreenshot = false;
  NovaModel? _selectedModel;
  CustomModel? _selectedCustomModel;
  final AttachmentManager _attachmentManager = AttachmentManager.instance;
  StreamSubscription<void>? _historyClearedSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<ContextBudgetEstimate>? _contextBudgetSub;
  ContextBudgetEstimate? _contextBudget;
  int _lastContextBudgetWarnPercent = 0;
  List<String> _followUpSuggestions = [];
  bool _isLoadingSuggestions = false;
  bool _suggestionReroll = false;
  int _suggestionRequestId = 0;
  bool _memoryWarningShown = false;
  bool _autoSendFromAssistantTrigger = false;
  bool _debugMode = false;
  int? _debugMemoryMb;
  Timer? _memoryPollTimer;
  Timer? _saveDebounceTimer;
  Completer<void>? _screenshotLoadedCompleter;
  bool _showSearch = false;
  int _searchMatchCount = 0;
  int _currentSearchMatch = 0;
  List<int> _searchMatchIndices = [];
  ChatBubbleTheme _chatTheme = ChatBubbleTheme.defaultTheme;
  RecordingState _recordingState = RecordingState.idle;
  StreamSubscription<RecordingState>? _recordingStateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedModel = ModelOrchestrator.instance.preferredModelType;
    _selectedCustomModel = ModelOrchestrator.instance.preferredCustomModel;
    if (_selectedCustomModel != null) {
      _selectedModel = null;
    }
    _loadThinkingMode();
    _loadDebugMode();
    _loadBubbleTheme();
    _loadInitialScreenshot();
    _loadHistory();
    _requestPermissions();
    _listenToModelStatus();
    _checkModelAvailability();
    _recordingStateSub = AudioRecorderService.instance.onStateChanged.listen((
      state,
    ) {
      if (mounted) {
        setState(() => _recordingState = state);
      }
    });
    _historyClearedSub = ModelOrchestrator.instance.historyClearedStream.listen(
      (_) {
        if (mounted) {
          setState(() {
            _messages.clear();
            _contextBudget = null;
            _lastContextBudgetWarnPercent = 0;
          });
        }
      },
    );
    _contextBudgetSub = ModelOrchestrator.instance.contextNearLimitStream.listen((
      estimate,
    ) {
      if (!mounted) return;
      final percent = (estimate.usageRatio * 100).round();
      setState(() => _contextBudget = estimate);
      // Avoid spamming: only show the SnackBar when the bucket changes
      // (>=70 % info, >=85 % warning). User can dismiss freely.
      final bucket = percent >= 85
          ? 85
          : percent >= 70
          ? 70
          : 0;
      if (bucket > _lastContextBudgetWarnPercent) {
        _lastContextBudgetWarnPercent = bucket;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bucket >= 85
                  ? 'Context near limit ($percent%). Next send will auto-compact history.'
                  : 'Context at $percent% of the model window.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
    unawaited(ShizukuService.instance.ensureLoaded());
    ShizukuService.instance.confirmationHandler = _confirmForceStop;
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _inputController.text = widget.initialPrompt!;
        if (widget.autoSendInitialPrompt) {
          _sendMessage();
        }
      });
    }
  }

  Future<void> _loadHistory() async {
    if (widget.conversationId != null) {
      final conversation = await ChatHistoryService.getConversation(
        widget.conversationId!,
      );
      if (conversation != null && mounted) {
        setState(() {
          _messages.addAll(conversation.messages);
          _refreshLocalContextBudget();
        });
        ConversationSummaryService.instance.activeSummary =
            conversation.summary;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(force: true),
        );
      }
    } else {
      final history = await ChatHistoryService.load();
      if (mounted && history.isNotEmpty) {
        setState(() {
          _messages.addAll(history);
          _refreshLocalContextBudget();
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToBottom(force: true),
        );
      } else if (mounted) {
        // Empty main chat — drop any leftover summary from a prior session.
        ConversationSummaryService.instance.activeSummary = null;
        ModelOrchestrator.instance.setPendingReplayMessages(const []);
      }
    }
  }

  void _scheduleSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveMessages());
    });
  }

  Future<void> _saveMessages() async {
    final persistable = _messages.where(_isPersistableMessage).toList();
    if (widget.conversationId != null) {
      final conversation = await ChatHistoryService.getConversation(
        widget.conversationId!,
      );
      if (conversation != null) {
        final updated = conversation.copyWith(messages: List.from(persistable));
        await ChatHistoryService.updateConversation(updated);
        await ConversationSummaryService.instance.maybeUpdateSummary(updated);
      }
    } else {
      await ChatHistoryService.save(persistable);
      final conversations = await ChatHistoryService.loadConversations();
      if (conversations.isNotEmpty) {
        await ConversationSummaryService.instance.maybeUpdateSummary(
          conversations.first.copyWith(messages: List.from(persistable)),
        );
      }
    }
  }

  /// Keeps completed turns with text, images, or tool calls; drops streaming
  /// placeholders and empty shells.
  bool _isPersistableMessage(ChatMessage m) {
    if (m.isStreaming || m.isError) return false;
    if (m.text.trim().isNotEmpty) return true;
    if (m.imageData != null && m.imageData!.isNotEmpty) return true;
    if (m.toolCalls != null && m.toolCalls!.trim().isNotEmpty) return true;

    return false;
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
    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            micStatus.isPermanentlyDenied
                ? 'Microphone permission denied permanently. Enable in Settings.'
                : 'Microphone permission needed for voice input.',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    }
    await Permission.photos.request();
  }

  void _listenToModelStatus() {
    _statusSub?.cancel();
    _statusSub = ModelOrchestrator.instance.statusStream.listen((status) {
      if (!mounted) return;
      if (status != _status) {
        setState(() => _status = status);
      }
      _checkModelAvailability();
      if (status.startsWith('NEED_DOWNLOAD_CONSENT:')) {
        final modelName = status.substring('NEED_DOWNLOAD_CONSENT:'.length);
        _showDownloadConsentDialog(modelName);
      }
      if (!_memoryWarningShown && status.contains('Gemma 4 E2B')) {
        final warning = PlatformAdaptationService.instance.getMemoryWarning(
          NovaModel.gemma4E2b,
        );
        if (warning != null && mounted) {
          _memoryWarningShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(warning),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    });
  }

  Future<void> _loadDebugMode() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('settings_debug_mode') ?? false;
    if (!mounted) return;
    setState(() => _debugMode = enabled);
    _configureMemoryPolling(enabled);
  }

  Future<void> _loadBubbleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName =
        prefs.getString('settings_bubble_theme') ?? 'defaultTheme';
    final type = ChatBubbleThemeType.values.firstWhere(
      (t) => t.name == themeName,
      orElse: () => ChatBubbleThemeType.defaultTheme,
    );
    if (mounted) {
      setState(() => _chatTheme = ChatBubbleTheme.fromType(type));
    }
  }

  void _configureMemoryPolling(bool enabled) {
    _memoryPollTimer?.cancel();
    _memoryPollTimer = null;
    if (!enabled) return;

    _memoryPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final mb = await MemoryDiagnosticsService.instance.readProcessMemoryMb();
      if (mounted && mb != _debugMemoryMb) {
        setState(() => _debugMemoryMb = mb);
      }
    });
  }

  bool get _isAutoMode =>
      _selectedModel == null && _selectedCustomModel == null;

  NovaModel get _effectiveModel =>
      ModelOrchestrator.instance.predictEffectiveModel(
        query: _inputController.text,
        thinkingMode: _thinkingMode,
        hasImage: _hasAttachments,
        forcePrimaryModel: _isAutoMode,
      );

  String get _effectiveModelLabel {
    if (_selectedCustomModel != null) return _selectedCustomModel!.displayName;
    if (_isAutoMode) return 'Auto → ${_effectiveModel.displayName}';

    return _effectiveModel.displayName;
  }

  bool get _hasAttachments =>
      _currentScreenshot != null || _attachmentManager.attachments.isNotEmpty;

  int get _historyTokenEstimate {
    final text = _messages
        .where((m) => !m.isStreaming && !m.isError)
        .map((m) => m.text)
        .join(' ');

    return MessageLimits.estimateTokens(text);
  }

  int get _messageHardLimit {
    if (_selectedCustomModel != null) {
      return MessageLimits.hardLimit(
        MessageLimitTier.large,
        hasAttachments: _hasAttachments,
      );
    }

    return MessageLimits.maxUserCharsForInference(
      effectiveModel: _effectiveModel,
      historyTokenEstimate: _historyTokenEstimate,
      hasAttachments: _hasAttachments,
      highContext: ModelOrchestrator.instance.highContextEnabled,
    );
  }

  int get _messageSoftLimit {
    if (_selectedCustomModel != null) {
      return MessageLimits.softLimit(
        MessageLimitTier.large,
        hasAttachments: _hasAttachments,
      );
    }

    return MessageLimits.softUserCharsForInference(
      effectiveModel: _effectiveModel,
      historyTokenEstimate: _historyTokenEstimate,
      hasAttachments: _hasAttachments,
      highContext: ModelOrchestrator.instance.highContextEnabled,
    );
  }

  bool _isOverHardLimitFor(String text) => text.length > _messageHardLimit;

  Future<void> _maybeAutoCompact() async {
    if (!ModelOrchestrator.instance.autoCompactEnabled) return;
    final maxChars = MessageLimits.maxUserCharsForInference(
      effectiveModel: _effectiveModel,
      historyTokenEstimate: _historyTokenEstimate,
      hasAttachments: _hasAttachments,
      highContext: ModelOrchestrator.instance.highContextEnabled,
    );
    if (maxChars >= 800) return;

    Conversation? conversation;
    if (widget.conversationId != null) {
      conversation = await ChatHistoryService.getConversation(
        widget.conversationId!,
      );
    }
    conversation ??= Conversation(
      id: widget.conversationId,
      messages: List.from(_messages),
    );
    conversation = conversation.copyWith(messages: List.from(_messages));

    final result = await ConversationSummaryService.instance.compactNow(
      conversation,
    );
    await ModelOrchestrator.instance.applyCompactedReplay(
      result.retainedMessages,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Context compacted to free space')),
      );
    }
  }

  Future<void> _manualCompact() async {
    if (_isGenerating) return;

    Conversation? conversation;
    if (widget.conversationId != null) {
      conversation = await ChatHistoryService.getConversation(
        widget.conversationId!,
      );
    }
    conversation ??= Conversation(
      id: widget.conversationId,
      messages: List.from(_messages),
    );
    conversation = conversation.copyWith(messages: List.from(_messages));

    final result = await ConversationSummaryService.instance.compactNow(
      conversation,
    );
    await ModelOrchestrator.instance.applyCompactedReplay(
      result.retainedMessages,
    );
    if (mounted) {
      setState(() {
        _messages
          ..clear()
          ..addAll(result.retainedMessages);
        _refreshLocalContextBudget();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Context compacted to free space')),
      );
    }
  }

  void _refreshLocalContextBudget() {
    if (_messages.isEmpty) {
      _contextBudget = null;
      return;
    }
    final model =
        _selectedModel ??
        ModelOrchestrator.instance.preferredModelType ??
        NovaModel.gemma4E2b;
    final historyTokens = _messages.fold<int>(
      0,
      (sum, m) => sum + MessageLimits.estimateRealTokens(m.text, model: model),
    );
    final customKv = _selectedCustomModel?.maxContextTokens;
    final estimate = MessageLimits.estimatePromptTokens(
      model: model,
      systemPrompt: '',
      query: '',
      historyTokenEstimate: historyTokens,
      highContext: ModelOrchestrator.instance.highContextEnabled,
    );
    if (customKv != null && customKv > 0) {
      final ratio = ModelOrchestrator.instance.highContextEnabled
          ? MessageLimits.highContextBudgetRatio
          : MessageLimits.contextBudgetRatio;
      final ceiling = (customKv * ratio).round();
      _contextBudget = ContextBudgetEstimate(
        estimatedTokens: estimate.estimatedTokens,
        kvLimit: customKv,
        usableCeiling: ceiling,
        systemPromptTokens: estimate.systemPromptTokens,
        queryTokens: estimate.queryTokens,
        historyTokens: historyTokens,
        ragTokens: estimate.ragTokens,
        attachmentTokens: estimate.attachmentTokens,
        visionTokens: estimate.visionTokens,
        overheadTokens: estimate.overheadTokens,
      );
    } else {
      _contextBudget = estimate;
    }
  }

  Future<void> _showContextBudgetSheet() async {
    final budget = _contextBudget;
    if (budget == null) return;
    final percent = (budget.usageRatio * 100).clamp(0, 999).round();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Context $percent%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${budget.estimatedTokens} / ${budget.usableCeiling} tokens '
                '(KV ${budget.kvLimit})',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.compress, color: Colors.white70),
                title: const Text(
                  'Compact history',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Summarize older turns to free space',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'compact'),
              ),
              ListTile(
                leading: const Icon(Icons.add_comment, color: Colors.white70),
                title: const Text(
                  'New chat',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Start fresh with a clean context window',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'new'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'compact') {
      await _manualCompact();
    } else if (action == 'new') {
      await _startFreshChat();
    }
  }

  Future<void> _startFreshChat() async {
    await ModelOrchestrator.instance.clearHistory();
    final conv = await ChatHistoryService.createConversation();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AssistantScreen(conversationId: conv.id),
      ),
    );
  }

  void _fillComposer(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.collapsed(offset: text.length);
    _inputFocus.requestFocus();
  }

  Future<void> _showClipboardActions() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (clip.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Clipboard is empty')));

      return;
    }

    final preview = clip.length > 80 ? '${clip.substring(0, 80)}…' : clip;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Clipboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.content_paste, color: Colors.white70),
                title: const Text(
                  'Paste',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, 'paste'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.analytics_outlined,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Analyze clipboard',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Send with an analyze prompt',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'analyze'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'paste') {
      final current = _inputController.text;
      final merged = current.isEmpty ? clip : '$current$clip';
      _fillComposer(merged);
    } else if (action == 'analyze') {
      _applySuggestion('Analyze the following clipboard content:\n\n$clip');
    }
  }

  bool _canSendFor(String text) =>
      text.trim().isNotEmpty &&
      !_isGenerating &&
      !ModelOrchestrator.instance.isBusy &&
      !_isOverHardLimitFor(text);

  String? get _lastUserMessage {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.isUser && msg.text.trim().isNotEmpty) return msg.text.trim();
    }

    return null;
  }

  String? get _lastAssistantMessage {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (!msg.isUser &&
          !msg.isStreaming &&
          !msg.isError &&
          msg.text.trim().isNotEmpty) {
        return msg.text.trim();
      }
    }

    return null;
  }

  void _clearFollowUpSuggestions() {
    if (_followUpSuggestions.isEmpty && !_isLoadingSuggestions) return;
    setState(() {
      _followUpSuggestions = [];
      _isLoadingSuggestions = false;
    });
  }

  void _filterMessages(String query) {
    setState(() {
      if (query.isEmpty) {
        _searchMatchIndices = [];
        _searchMatchCount = 0;
        _currentSearchMatch = 0;
        return;
      }
      final lower = query.toLowerCase();
      _searchMatchIndices = _messages
          .asMap()
          .entries
          .where((e) => e.value.text.toLowerCase().contains(lower))
          .map((e) => e.key)
          .toList();
      _searchMatchCount = _searchMatchIndices.length;
      _currentSearchMatch = _searchMatchCount > 0 ? 1 : 0;
    });
  }

  void _nextSearchMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentSearchMatch = _currentSearchMatch % _searchMatchCount + 1;
    });
  }

  void _previousSearchMatch() {
    if (_searchMatchIndices.isEmpty) return;
    setState(() {
      _currentSearchMatch = _currentSearchMatch <= 1
          ? _searchMatchCount
          : _currentSearchMatch - 1;
    });
  }

  Future<void> _onBulbPressed() async {
    if (_isGenerating || ModelOrchestrator.instance.isBusy) return;

    final requestId = ++_suggestionRequestId;

    setState(() {
      _isLoadingSuggestions = true;
      _followUpSuggestions = [];
    });

    final suggestions = await FollowUpSuggestionService.instance.suggest(
      lastUserMessage: _lastUserMessage,
      lastAssistantMessage: _lastAssistantMessage,
      different: _suggestionReroll,
    );

    if (!mounted || requestId != _suggestionRequestId) return;
    setState(() {
      _followUpSuggestions = suggestions;
      _isLoadingSuggestions = false;
      _suggestionReroll = false;
    });
  }

  Future<void> _rerollSuggestions() async {
    _suggestionReroll = true;
    await _onBulbPressed();
  }

  void _applySuggestion(String text) {
    if (ModelOrchestrator.instance.isBusy || _isGenerating) {
      _inputController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wait for the current response to finish.'),
          duration: Duration(seconds: 2),
        ),
      );

      return;
    }

    _inputController.text = text;
    unawaited(_sendMessage());
  }

  /// Whether the query asks about the device screen / a screenshot.
  bool _wantsDeviceScreen(String query, {required bool hasImage}) {
    if (hasImage) return false;
    final q = query.toLowerCase();

    return q.contains('screenshot') ||
        q.contains('capture the screen') ||
        q.contains('capture my screen') ||
        q.contains("what's on my screen") ||
        q.contains('whats on my screen') ||
        q.contains('what is on my screen') ||
        q.contains('on my screen') ||
        (q.contains('screen') &&
            (q.contains('look') ||
                q.contains('see') ||
                q.contains('show') ||
                q.contains('what')));
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
    ShizukuService.instance.confirmationHandler = null;
    WidgetsBinding.instance.removeObserver(this);
    _historyClearedSub?.cancel();
    _statusSub?.cancel();
    _contextBudgetSub?.cancel();
    _memoryPollTimer?.cancel();
    _saveDebounceTimer?.cancel();
    _recordingStateSub?.cancel();
    WakelockPlus.disable();
    if (_screenshotLoadedCompleter != null &&
        !_screenshotLoadedCompleter!.isCompleted) {
      _screenshotLoadedCompleter!.complete();
    }
    _screenshotLoadedCompleter = null;
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<bool> _confirmForceStop(String packageName) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Force-stop app?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Force-stop $packageName?\n\n'
          'Unsaved work in that app may be lost.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Force-stop'),
          ),
        ],
      ),
    );

    return ok == true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final shouldRelease = ModelReleasePolicy.shouldReleaseOnPause(
        keepModelWarm: ModelOrchestrator.instance.keepModelWarm,
        isStreaming: ModelOrchestrator.instance.isStreaming,
      );
      if (shouldRelease) {
        ModelOrchestrator.instance.releaseIdleResources(force: true);
      }
    } else if (state == AppLifecycleState.resumed) {
      _checkModelAvailability();
      _detectModelEviction();
    }
  }

  Future<void> _detectModelEviction() async {
    final orch = ModelOrchestrator.instance;
    // Only check if model was previously loaded and keep-warm is enabled
    if (!orch.keepModelWarm || orch.isModelLoaded) return;
    // Check if a model should be loaded but was evicted (e.g. by HyperOS)
    final prefs = await SharedPreferences.getInstance();
    final hadModel = prefs.getString('settings_preferred_model_override');
    if (hadModel == null || hadModel == 'none') return;
    // Model was expected but not loaded — show eviction notice
    if (!mounted) return;
    final ignoringOptimizations = await orch.isIgnoringBatteryOptimizations();
    if (!ignoringOptimizations) {
      _showBatteryOptimizationGuide();
    }
  }

  void _showBatteryOptimizationGuide() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep Nova Responsive'),
        content: const Text(
          'Your device may be stopping Nova in the background, '
          'causing the AI model to reload.\n\n'
          'To fix this: Open Settings → Apps → Nova → '
          'Battery → "No restrictions".\n\n'
          'On Xiaomi/Poco: also disable "Pause app activity if unused".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadInitialScreenshot() async {
    _screenshotLoadedCompleter = Completer<void>();
    _isLoadingInitialScreenshot = true;
    try {
      // Fetch screenshot and assistant-launch flag in parallel
      final results = await Future.wait([
        ScreenshotService.instance.getLatestScreenshot(),
        ScreenshotService.instance.wasLaunchedFromSystemAssistant(),
      ]);
      final screenshot = results[0] as Uint8List?;
      final isAssistantLaunch =
          (results[1] as bool?) ?? false || widget.isSystemAssistantLaunch;

      if (mounted) {
        setState(() {
          _currentScreenshot = screenshot;
          _isLoadingInitialScreenshot = false;
        });
        // Screenshot came from system assistant trigger — auto-send with context.
        // Only auto-send when the screen was actually opened via the system assistant
        // (not on regular "New Chat" where a stale cached screenshot might linger).
        if (screenshot != null && _messages.isEmpty && isAssistantLaunch) {
          _autoSendFromAssistantTrigger = true;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitialScreenshot = false);
      }
      _screenshotLoadedCompleter?.complete();
    }
    // Auto-send when triggered via system assistant button with a fresh screenshot
    if (_autoSendFromAssistantTrigger && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_autoSendFromAssistantTrigger) return;
        _autoSendFromAssistantTrigger = false;
        _inputController.text = 'What\'s on my screen?';
        _sendMessage();
      });
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.position.pixels;

        if (force || (maxScroll - currentScroll) < 120.0) {
          _scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
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
    ModelOrchestrator.instance.invalidateSessionForReplay(
      _messages.where((m) => !m.isStreaming).toList(),
    );

    // Re-send
    _inputController.text = userText;
    _sendMessage();
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
      _messages.where((m) => !m.isStreaming).toList(),
    );

    // Re-send the user message
    _inputController.text = userText;
    _sendMessage();
  }

  Future<void> _editUserMessage(int userIndex) async {
    if (_isGenerating || userIndex < 0 || userIndex >= _messages.length) {
      return;
    }
    final message = _messages[userIndex];
    if (!message.isUser) return;

    final controller = TextEditingController(text: message.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Edit message',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Edit your message…',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Resend'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    if (result == null || result.isEmpty || !mounted) return;

    await TtsService.instance.stop();
    if (!mounted) return;
    setState(() {
      _messages.removeRange(userIndex, _messages.length);
    });
    ModelOrchestrator.instance.invalidateSessionForReplay(
      _messages.where((m) => !m.isStreaming).toList(),
    );
    // #region agent log
    unawaited(
      AgentDebugLog.log(
        hypothesisId: 'A',
        location: 'assistant_screen.dart:_editUserMessage',
        message: 'Edit truncated UI history; session invalidated',
        data: {'remaining': _messages.length, 'newQueryLen': result.length},
        runId: 'post-fix',
      ),
    );
    // #endregion
    _inputController.text = result;
    unawaited(_sendMessage());
  }

  /// Non-destructive Gemini-style branch: new chat with prefix through [index].
  Future<void> _branchFromMessage(int index) async {
    final convId = widget.conversationId;
    if (convId == null ||
        _isGenerating ||
        index < 0 ||
        index >= _messages.length) {
      return;
    }

    await _saveMessages();
    final branched = await ChatHistoryService.branchFromMessage(convId, index);
    if (!mounted) return;
    if (branched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start new chat from here')),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Started new chat from here'),
        duration: Duration(seconds: 2),
      ),
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AssistantScreen(conversationId: branched.id),
      ),
    );
  }

  Future<void> _speakMessage(String text) async {
    await TtsService.instance.speak(text);
  }

  List<Tool> _toolsForQuery(String query, {bool hasImage = false}) {
    final tools = <Tool>[];
    final q = query.toLowerCase();

    // Core tools (no screenshot — gated below)
    tools.addAll([
      NovaTools.getTime,
      NovaTools.setAlarm,
      NovaTools.cancelAlarm,
      NovaTools.openSettings,
      NovaTools.openApp,
      NovaTools.openAppInfo,
      NovaTools.openBatterySettings,
    ]);

    if (ShizukuService.instance.shouldExposeForceStopTool) {
      tools.add(NovaTools.forceStopApp);
    }

    // Only offer screen capture when the user asks for the *device screen*
    // and no image is already attached (gallery / prior capture).
    final wantsDeviceScreen = _wantsDeviceScreen(query, hasImage: hasImage);
    if (wantsDeviceScreen) {
      tools.add(NovaTools.takeScreenshot);
    }

    // Weather only if explicitly asked
    if (q.contains('weather') ||
        q.contains('temperature') ||
        q.contains('forecast')) {
      tools.add(NovaTools.getWeather);
    }

    // SMS only if explicitly asked
    if (q.contains('send') &&
        (q.contains('sms') || q.contains('text') || q.contains('message'))) {
      tools.add(NovaTools.sendSms);
    }

    // Web search only if explicitly asked
    if (q.contains('search') ||
        q.contains('look up') ||
        q.contains('find online') ||
        q.contains('google')) {
      tools.add(NovaTools.searchWeb);
    }

    // Connected MCP tools (when a server is connected and tools discovered)
    tools.addAll(McpService.instance.enabledTools);

    return tools;
  }

  Future<void> _stopGeneration() async {
    await ModelOrchestrator.instance.stopGeneration();
    WakelockPlus.disable();
    // Avoid reusing a half-written MediaPipe session after cancel.
    ModelOrchestrator.instance.invalidateSessionForReplay(_messages.toList());
    if (!mounted) return;
    final idx = _messages.lastIndexWhere((m) => !m.isUser);
    if (idx != -1) {
      // Keep model-visible text clean; UI shows stop via wasCancelled.
      setState(() {
        _messages[idx] = _messages[idx].copyWith(
          isStreaming: false,
          wasCancelled: true,
        );
        _isGenerating = false;
      });
    } else {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    if (ModelOrchestrator.instance.isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Model is loading or responding. Please wait.'),
          duration: Duration(seconds: 2),
        ),
      );

      return;
    }

    if (_isOverHardLimitFor(text)) {
      final error = _selectedCustomModel != null
          ? MessageLimits.validateLength(
              text: text,
              isCustomModel: true,
              hasAttachments: _hasAttachments,
            )
          : MessageLimits.validateTokenBudget(
              text: text,
              effectiveModel: _effectiveModel,
              historyTokenEstimate: _historyTokenEstimate,
              hasAttachments: _hasAttachments,
              highContext: ModelOrchestrator.instance.highContextEnabled,
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error ?? 'Message is too long.')));

      return;
    }

    await _maybeAutoCompact();

    // Screen questions need a real image; SmolLM cannot see the device.
    final hasImageAlready =
        _currentScreenshot != null ||
        _attachmentManager.attachments.any(
          (a) => a.filePath != null && DocumentExtractor.isImageFile(a.name),
        );
    if (_wantsDeviceScreen(text, hasImage: hasImageAlready) &&
        _currentScreenshot == null) {
      await _captureAndAttachScreenshot();
      if (!mounted) return;
      if (_currentScreenshot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Screen capture is required to answer "what\'s on my screen?". '
              'Allow capture or attach a photo.',
            ),
            duration: Duration(seconds: 3),
          ),
        );

        return;
      }
    }

    // Wait for initial screenshot to load if still loading (from assistant mode)
    // This ensures screenshot is captured before model selection happens
    if (_isLoadingInitialScreenshot && _currentScreenshot == null) {
      debugPrint('Waiting for initial screenshot to load...');
      await _screenshotLoadedCompleter?.future;
      debugPrint('Screenshot loaded: ${_currentScreenshot != null}');
    }

    ModelOrchestrator.instance.setPendingReplayMessages(
      _messages.where((m) => !m.isStreaming).toList(),
    );

    _inputController.clear();
    _clearFollowUpSuggestions();

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

    if (TtsService.instance.isSpeaking) {
      await TtsService.instance.stop();
    }

    _scheduleSave();

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

    // Enable wakelock during streaming if setting is on
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('settings_screen_timeout_stream') ?? true) {
      WakelockPlus.enable();
    }

    try {
      String accumulated = '';

      final hasImageAttachment =
          _currentScreenshot != null ||
          _attachmentManager.attachments.any(
            (a) => a.filePath != null && DocumentExtractor.isImageFile(a.name),
          );

      await for (final result in ModelOrchestrator.instance.processMessage(
        query: text,
        screenshot: _currentScreenshot,
        thinkingMode: _thinkingMode,
        tools: _toolsForQuery(text, hasImage: hasImageAttachment),
        attachments: _attachmentManager.attachments,
        // Force heavy model only in auto mode; respect model overrides
        forcePrimaryModel:
            _selectedModel == null && _selectedCustomModel == null,
      )) {
        if (!mounted) break;

        accumulated = result.text;

        final idx = _messages.lastIndexWhere((m) => m.id == assistantId);
        if (idx != -1) {
          final prior = _messages[idx];
          // After Stop, keep wasCancelled and do not replace with empty /
          // stale-session warnings from a cancelled stream.
          if (prior.wasCancelled &&
              !result.isStreaming &&
              accumulated.trim().isEmpty) {
            setState(() {
              _messages[idx] = prior.copyWith(
                isStreaming: false,
                wasCancelled: true,
                modelName: result.model.displayName,
                inferenceTimeMs:
                    result.inferenceTimeMs ?? prior.inferenceTimeMs,
              );
            });
          } else {
            setState(() {
              _messages[idx] = prior.copyWith(
                text: accumulated,
                modelName: result.model.displayName,
                isStreaming: result.isStreaming,
                isError: false,
                wasCancelled: prior.wasCancelled,
                toolCalls: result.toolCalls != null
                    ? jsonEncode(result.toolCalls)
                    : null,
                thinking: result.thinking,
                inferenceTimeMs:
                    result.inferenceTimeMs ?? prior.inferenceTimeMs,
              );
            });
          }
          _scrollToBottom(force: true);
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
      if (mounted) {
        setState(() {
          _isGenerating = false;
          if (!_shouldPreserveScreenshot) {
            _currentScreenshot = null;
          }
          _shouldPreserveScreenshot = false;
        });
      } else {
        _isGenerating = false;
        _shouldPreserveScreenshot = false;
      }
      _scheduleSave();
      _attachmentManager.clear();
      WakelockPlus.disable();
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

  Future<void> _showAttachSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.screenshot_monitor_outlined,
                color: Colors.white70,
              ),
              title: const Text(
                'Screenshot',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'screenshot'),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: Colors.white70,
              ),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.white70),
              title: const Text('File', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.white70),
              title: const Text('URL', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'screenshot':
        await _captureAndAttachScreenshot();
      case 'gallery':
        await _pickImageFromGallery();
      case 'file':
        await _pickFile();
      case 'url':
        _showUrlDialog();
    }
  }

  Future<void> _showModelSelectorSheet(BuildContext context) async {
    final isAutoMode = _selectedModel == null && _selectedCustomModel == null;

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ModelSelectorSheet(
        currentSelection: _selectedModel,
        currentCustomModel: _selectedCustomModel,
        isAutoMode: isAutoMode,
        onModelSelected: (model) {
          _selectedModel = model;
          _selectedCustomModel = null;
          if (model != null) {
            ModelOrchestrator.instance.preferredModelType = model;
            ModelOrchestrator.instance.preferredCustomModel = null;
          }
          setState(() {});
        },
        onCustomModelSelected: (model) {
          _selectedCustomModel = model;
          _selectedModel = null;
          if (model != null) {
            ModelOrchestrator.instance.preferredCustomModel = model;
            ModelOrchestrator.instance.preferredModelType = null;
          }
          setState(() {});
        },
        onAutoModeChanged: (auto) {
          if (auto) {
            _selectedModel = null;
            _selectedCustomModel = null;
            ModelOrchestrator.instance.clearModelOverride();
          }
          setState(() {});
        },
        onImportModel: () => Navigator.pop(context, 'import'),
      ),
    );

    if (result == 'import' && mounted) {
      await _showCustomModelImportSheet();
    }
  }

  Future<void> _showCustomModelImportSheet() async {
    final imported = await showModalBottomSheet<CustomModel>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const CustomModelImportSheet(),
    );

    if (!mounted || imported == null) return;

    setState(() {
      _selectedCustomModel = imported;
      _selectedModel = null;
    });
    ModelOrchestrator.instance.preferredCustomModel = imported;
    ModelOrchestrator.instance.preferredModelType = null;
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
      final result = await FilePicker.pickFiles(type: FileType.any);

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
    final isLoadingModel = ModelOrchestrator.instance.isLoadingModel;

    return Scaffold(
      backgroundColor: _chatTheme.backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildAppBar(),
                if (_currentScreenshot != null) _buildScreenshotIndicator(),
                if (_attachmentManager.hasAttachments)
                  _buildAttachmentIndicator(),
                if (_offlineMode) _buildOfflineBanner(),
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];

                            return RepaintBoundary(
                              child: ChatBubble(
                                message: msg,
                                theme: _chatTheme,
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
                                  final attribution = msg.isUser
                                      ? ''
                                      : '\n\n— ${msg.modelName ?? "Nova"} · ${_formatTimestamp(msg.timestamp)}';
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: '${msg.text}$attribution',
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                onReactionRequest: () =>
                                    _showReactionPicker(index),
                                onReactionChipTap: (emoji) =>
                                    _toggleReaction(index, emoji),
                                onRegenerate:
                                    !msg.isUser &&
                                        !msg.isError &&
                                        !msg.isStreaming
                                    ? () => _regenerateResponse(index)
                                    : null,
                                onSpeak:
                                    !msg.isUser &&
                                        !msg.isError &&
                                        !msg.isStreaming &&
                                        TtsService.instance.isEnabled
                                    ? () => _speakMessage(msg.text)
                                    : null,
                                onEdit: msg.isUser && !_isGenerating
                                    ? () => _editUserMessage(index)
                                    : null,
                                onBranchFromHere:
                                    widget.conversationId != null &&
                                        !_isGenerating &&
                                        !msg.isStreaming &&
                                        !msg.isError
                                    ? () => unawaited(_branchFromMessage(index))
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
                _buildStatusBar(),
                _buildInputBar(),
              ],
            ),
            if (_debugMode) _buildDebugBanner(),
            if (isLoadingModel)
              _buildModelLoadingOverlay()
            else if (ModelOrchestrator.instance.isPreparingChat)
              _buildChatPrepOverlay(),
            if (_showSearch)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: InChatSearchBar(
                  onSearch: _filterMessages,
                  onClose: () => setState(() => _showSearch = false),
                  matchCount: _searchMatchCount,
                  currentMatch: _currentSearchMatch,
                  onNext: _nextSearchMatch,
                  onPrevious: _previousSearchMatch,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelLoadingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF6C63FF)),
                const SizedBox(height: 16),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'First compile can take 1–2 minutes. Do not send yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatPrepOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF6C63FF),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugBanner() {
    final orchestrator = ModelOrchestrator.instance;
    final ram = _debugMemoryMb != null ? '$_debugMemoryMb MB' : '…';
    final modelState = orchestrator.isLoadingModel
        ? 'loading'
        : orchestrator.isModelLoaded
        ? 'loaded'
        : 'idle';
    final streamState = orchestrator.isStreaming ? 'streaming' : 'idle';
    final contextUsage = _contextBudget == null
        ? 'ctx: idle'
        : 'ctx: ${(_contextBudget!.usageRatio * 100).round()}% '
              '(${_contextBudget!.estimatedTokens}/${_contextBudget!.kvLimit})';

    return Positioned(
      left: 8,
      right: 8,
      bottom: 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'DEBUG  RAM: $ram  |  Model: $modelState  |  Stream: $streamState  |  '
            '$_effectiveModelLabel  |  $contextUsage',
            style: const TextStyle(color: Colors.white60, fontSize: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          if (widget.conversationId != null)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: 'Back to chat history',
            )
          else
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
          const SizedBox(width: 8),
          // Model picker
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
                      _selectedModel == null
                          ? Icons.auto_awesome
                          : Icons.account_tree,
                      size: 16,
                      color: const Color(0xFF6C63FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _selectedModel?.displayName ?? 'Auto',
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
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ChatHistoryScreen(),
              ),
            ),
            icon: const Icon(Icons.history, color: Colors.grey),
            tooltip: 'Chat history',
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) async {
              switch (value) {
                case 'thinking':
                  setState(() => _thinkingMode = !_thinkingMode);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('settings_thinking_mode', _thinkingMode);
                case 'export_text':
                case 'export_json':
                  final content = value == 'export_text'
                      ? await ChatHistoryService.exportAsText()
                      : await ChatHistoryService.exportAsJson();
                  if (!mounted) return;
                  if (content == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nothing to export')),
                    );

                    return;
                  }
                  await ExportService.instance.shareText(
                    content,
                    value == 'export_text'
                        ? 'nova_export.txt'
                        : 'nova_export.json',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share sheet opened'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                case 'export_markdown':
                  final convId = widget.conversationId;
                  if (convId == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No active conversation')),
                      );
                    }
                    return;
                  }
                  final mdContent =
                      await ChatHistoryService.exportConversationAsMarkdown(
                        convId,
                      );
                  if (!mounted) return;
                  if (mdContent == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Export failed')),
                    );
                    return;
                  }
                  await ExportService.instance.shareText(
                    mdContent,
                    'nova_chat_${convId.substring(0, 8)}.md',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share sheet opened'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                case 'fork':
                  final convId = widget.conversationId;
                  if (convId == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No active conversation')),
                      );
                    }
                    return;
                  }
                  final messages = _messages;
                  if (messages.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nothing to fork')),
                      );
                    }
                    return;
                  }
                  final idx = await showDialog<int>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A2E),
                      title: const Text(
                        'Fork conversation',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: Text(
                        'Fork from message 1 of ${messages.length} '
                        '(0 = from start, ${messages.length - 1} = from '
                        'last)?',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, 0),
                          child: const Text('From start'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(ctx, messages.length - 1),
                          child: const Text('From last'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  );
                  if (idx == null) return;
                  final forked = await ChatHistoryService.forkConversation(
                    convId,
                    idx,
                  );
                  if (!mounted) return;
                  if (forked == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fork failed')),
                    );
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Forked: ${forked.previewTitle}'),
                      backgroundColor: const Color(0xFF6C63FF),
                    ),
                  );
                  _loadHistory();
                case 'compact':
                  if (!_isGenerating) await _manualCompact();
                case 'search':
                  setState(() => _showSearch = true);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'thinking',
                child: Text(
                  _thinkingMode ? 'Thinking mode: On' : 'Thinking mode: Off',
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export_text',
                child: Text('Export all as Text'),
              ),
              const PopupMenuItem<String>(
                value: 'export_json',
                child: Text('Export all as JSON'),
              ),
              const PopupMenuItem<String>(
                value: 'export_markdown',
                child: Text('Export current as Markdown'),
              ),
              const PopupMenuItem<String>(
                value: 'fork',
                child: Text('Fork conversation from here'),
              ),
              const PopupMenuItem<String>(
                value: 'compact',
                child: Text('Compact context'),
              ),
              PopupMenuItem<String>(
                value: 'search',
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.white70, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Search in chat',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
            child: const Icon(Icons.more_vert, color: Colors.grey),
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined, color: Colors.grey),
            tooltip: 'Settings',
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
    final starters = PromptPresetsService.instance.emptyStateStarters;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Hi, I\'m Nova',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
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
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Try a prompt',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: starters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final starter = starters[index];

                        return SuggestionChip(
                          label: starter.label,
                          onTap: () => _fillComposer(starter.prompt),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      SuggestionChip(
                        label: "What's on my screen?",
                        onTap: () => _applySuggestion("What's on my screen?"),
                      ),
                      SuggestionChip(
                        label: 'Set an alarm for 7:00 PM',
                        onTap: () =>
                            _applySuggestion('Set an alarm for 7:00 PM'),
                      ),
                      SuggestionChip(
                        label: 'Open Settings',
                        onTap: () => _applySuggestion('Open Settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    final budget = _contextBudget;
    final percent = budget == null
        ? null
        : (budget.usageRatio * 100).clamp(0, 999).round();
    final meterColor = percent == null
        ? Colors.grey
        : percent >= 85
        ? Colors.redAccent
        : percent >= 70
        ? Colors.amber
        : const Color(0xFF6C63FF);

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
          Expanded(
            child: Text(
              _status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
          if (percent != null) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showContextBudgetSheet,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: meterColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: meterColor.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        height: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (percent / 100).clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            color: meterColor,
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Context $percent%',
                        style: TextStyle(fontSize: 10, color: meterColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_thinkingMode) ...[
            const SizedBox(width: 8),
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
        ],
      ),
    );
  }

  void _toggleRecording() {
    final svc = AudioRecorderService.instance;
    if (svc.isRecording) {
      svc.stopRecording();
    } else if (_recordingState == RecordingState.paused) {
      svc.stopRecording();
    } else {
      svc.startRecording();
    }
  }

  Widget _buildRecordButton() {
    final isRec = _recordingState == RecordingState.recording;
    final isPaused = _recordingState == RecordingState.paused;
    final isActive = isRec || isPaused;

    if (isActive) {
      return GestureDetector(
        onTap: _toggleRecording,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRec ? Colors.redAccent : Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                AudioRecorderService.instance.formattedDuration,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.stop, color: Colors.redAccent, size: 18),
            ],
          ),
        ),
      );
    }

    return IconButton(
      onPressed: _toggleRecording,
      icon: const Icon(Icons.mic_outlined, color: Colors.grey),
      tooltip: 'Record audio',
    );
  }

  Widget _buildInputBar() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _inputController,
      builder: (context, value, child) {
        final text = value.text;
        final charCount = text.length;
        final canSend = _canSendFor(text);
        final counterColor = _isOverHardLimitFor(text)
            ? Colors.redAccent
            : charCount > _messageSoftLimit
            ? Colors.amber
            : Colors.grey[600];
        final busy = ModelOrchestrator.instance.isBusy;

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
              if (_isLoadingSuggestions || _followUpSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _isLoadingSuggestions
                            ? const SizedBox(
                                height: 32,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final suggestion
                                        in _followUpSuggestions)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: SuggestionChip(
                                          label: suggestion,
                                          onTap: () {
                                            if (!busy) {
                                              _applySuggestion(suggestion);
                                            }
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                      if (!_isLoadingSuggestions &&
                          _followUpSuggestions.isNotEmpty)
                        IconButton(
                          onPressed: busy ? null : _rerollSuggestions,
                          icon: const Icon(Icons.refresh, color: Colors.grey),
                          tooltip: 'More suggestions',
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    onPressed: _showAttachSheet,
                    icon: const Icon(Icons.attach_file, color: Colors.grey),
                    tooltip: 'Attach',
                  ),
                  IconButton(
                    onPressed: _showClipboardActions,
                    icon: const Icon(Icons.content_paste, color: Colors.grey),
                    tooltip: 'Paste / analyze clipboard',
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: busy || _isGenerating ? null : _onBulbPressed,
                    icon: const Icon(
                      Icons.lightbulb_outline,
                      color: Colors.grey,
                    ),
                    tooltip: 'Suggested follow-ups',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      maxLength: _messageHardLimit,
                      maxLengthEnforcement: MaxLengthEnforcement.none,
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
                        counterText: '',
                      ),
                      textInputAction: TextInputAction.send,
                      contextMenuBuilder: (context, editableTextState) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: [
                            ...editableTextState.contextMenuButtonItems,
                            ContextMenuButtonItem(
                              label: 'Analyze clipboard',
                              onPressed: () {
                                ContextMenuController.removeAny();
                                unawaited(_showClipboardActions());
                              },
                            ),
                          ],
                        );
                      },
                      onSubmitted: (_) {
                        if (canSend) _sendMessage();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  VoiceInputButton(
                    onPartial: (partial) {
                      if (!mounted) return;
                      _inputController.text = partial;
                      _inputController.selection = TextSelection.collapsed(
                        offset: partial.length,
                      );
                    },
                    onTranscription: (transcript) {
                      if (!mounted || transcript.isEmpty) return;
                      _inputController.text = transcript;
                      if (_isGenerating || ModelOrchestrator.instance.isBusy) {
                        // Leave full text in the field for the user to send.
                        return;
                      }
                      unawaited(_sendMessage());
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildRecordButton(),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      onPressed: _isGenerating
                          ? _stopGeneration
                          : (canSend ? _sendMessage : null),
                      icon: Icon(
                        _isGenerating ? Icons.stop_circle : Icons.send_rounded,
                        color: _isGenerating
                            ? Colors.redAccent
                            : (canSend ? const Color(0xFF6C63FF) : Colors.grey),
                      ),
                      tooltip: _isGenerating ? 'Stop' : 'Send',
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$charCount / $_messageHardLimit',
                      style: TextStyle(fontSize: 11, color: counterColor),
                    ),
                    if (_selectedCustomModel == null)
                      Text(
                        _effectiveModelLabel,
                        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
        ),
      );
      items.add(const Divider(color: Colors.white10, height: 1));
    }

    items.add(
      ListTile(
        leading: Icon(
          msg.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          color: msg.isPinned ? Colors.amber : Colors.white70,
          size: 20,
        ),
        title: Text(
          msg.isPinned ? 'Unpin' : 'Pin',
          style: const TextStyle(color: Colors.white),
        ),
        onTap: () {
          Navigator.pop(context);
          _togglePin(messageIndex);
        },
      ),
    );

    if (widget.conversationId != null &&
        !_isGenerating &&
        !msg.isStreaming &&
        !msg.isError) {
      items.add(const Divider(color: Colors.white10, height: 1));
      items.add(
        ListTile(
          leading: const Icon(
            Icons.fork_right,
            color: Colors.white70,
            size: 20,
          ),
          title: const Text(
            'New chat from here',
            style: TextStyle(color: Colors.white),
          ),
          onTap: () {
            Navigator.pop(context);
            unawaited(_branchFromMessage(messageIndex));
          },
        ),
      );
    }

    items.add(const Divider(color: Colors.white10, height: 1));

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
    _scheduleSave();
  }

  void _togglePin(int messageIndex) {
    setState(() {
      final msg = _messages[messageIndex];
      _messages[messageIndex] = msg.copyWith(isPinned: !msg.isPinned);
    });
    _scheduleSave();
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

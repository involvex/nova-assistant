import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/model_info.dart';
import 'package:uuid/uuid.dart';

/// A single chat session with its own history
class ChatSession {
  final String id;
  final String name;
  final NovaModel model;
  final InferenceChat chat;
  final DateTime createdAt;
  DateTime lastActiveAt;
  bool isActive;

  ChatSession({
    required this.id,
    required this.name,
    required this.model,
    required this.chat,
    required this.createdAt,
    this.isActive = true,
  }) : lastActiveAt = createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'model': model.name,
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'isActive': isActive,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final session = ChatSession(
      id: json['id'] as String,
      name: json['name'] as String,
      model: NovaModel.values.firstWhere(
        (e) => e.name == json['model'],
        orElse: () => NovaModel.smollm,
      ),
      chat: json['chat'] as InferenceChat,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isActive: json['isActive'] as bool? ?? true,
    );
    session.lastActiveAt = DateTime.parse(json['lastActiveAt'] as String);
    return session;
  }
}

/// Result from a parallel inference operation
class ParallelInferenceResult {
  final String sessionId;
  final String text;
  final NovaModel model;
  final bool isStreaming;
  final String? thinking;

  const ParallelInferenceResult({
    required this.sessionId,
    required this.text,
    required this.model,
    this.isStreaming = false,
    this.thinking,
  });
}

/// Service for managing multiple concurrent chat sessions
class ParallelSessionManager {
  static ParallelSessionManager? _instance;
  static ParallelSessionManager get instance =>
      _instance ??= ParallelSessionManager._();
  ParallelSessionManager._();

  static const _maxConcurrentSessions = 3;
  static const _uuid = Uuid();

  final Map<String, ChatSession> _sessions = {};
  final _sessionsController = StreamController<List<ChatSession>>.broadcast();
  Stream<List<ChatSession>> get sessionsStream => _sessionsController.stream;

  /// Get all active sessions
  List<ChatSession> get sessions => List.unmodifiable(_sessions.values);

  /// Get the number of active sessions
  int get activeSessionCount =>
      _sessions.values.where((s) => s.isActive).length;

  /// Check if we can create more sessions
  bool get canCreateSession => activeSessionCount < _maxConcurrentSessions;

  /// Create a new chat session
  Future<ChatSession?> createSession({
    required NovaModel model,
    String? name,
    String? systemInstruction,
    List<Tool> tools = const [],
  }) async {
    if (!canCreateSession) {
      debugPrint('ParallelSessionManager: Max concurrent sessions reached');
      return null;
    }

    try {
      // Get or create the model
      final inferenceModel = await _getOrCreateModel(model);
      if (inferenceModel == null) return null;

      // Create the chat
      final chat = await inferenceModel.createChat(
        systemInstruction: systemInstruction,
        tools: tools,
      );

      final session = ChatSession(
        id: _uuid.v4(),
        name: name ?? 'Chat ${_sessions.length + 1}',
        model: model,
        chat: chat,
        createdAt: DateTime.now(),
      );

      _sessions[session.id] = session;
      _notifyListeners();

      return session;
    } catch (e) {
      debugPrint('ParallelSessionManager: Failed to create session: $e');
      return null;
    }
  }

  /// Send a message to a specific session
  Stream<ParallelInferenceResult> sendMessage({
    required String sessionId,
    required String query,
    Uint8List? screenshot,
  }) async* {
    final session = _sessions[sessionId];
    if (session == null) {
      yield ParallelInferenceResult(
        sessionId: sessionId,
        text: 'Session not found',
        model: NovaModel.smollm,
      );
      return;
    }

    // Update last active time
    session.lastActiveAt = DateTime.now();

    // Create the message
    final message = screenshot != null
        ? Message.withImage(text: query, imageBytes: screenshot, isUser: true)
        : Message.text(text: query, isUser: true);

    await session.chat.addQuery(message);

    String fullResponse = '';
    String? currentThinking;

    await for (final event in session.chat.generateChatResponseAsync()) {
      if (event is TextResponse) {
        fullResponse += event.token;
        yield ParallelInferenceResult(
          sessionId: sessionId,
          text: fullResponse,
          model: session.model,
          isStreaming: true,
          thinking: currentThinking,
        );
      } else if (event is ThinkingResponse) {
        currentThinking = event.content;
        yield ParallelInferenceResult(
          sessionId: sessionId,
          text: fullResponse,
          model: session.model,
          isStreaming: true,
          thinking: currentThinking,
        );
      } else if (event is FunctionCallResponse) {
        // Handle function calls (simplified - in production, use ToolExecutorService)
        final toolResponse = Message.toolResponse(
          toolName: event.name,
          response: {'status': 'executed'},
        );
        await session.chat.addQuery(toolResponse);
      }
    }

    yield ParallelInferenceResult(
      sessionId: sessionId,
      text: fullResponse,
      model: session.model,
      isStreaming: false,
      thinking: currentThinking,
    );
  }

  /// Close a specific session
  Future<void> closeSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    try {
      await session.chat.close();
      session.isActive = false;
      _notifyListeners();
    } catch (e) {
      debugPrint('ParallelSessionManager: Error closing session: $e');
    }
  }

  /// Close all sessions
  Future<void> closeAllSessions() async {
    for (final session in _sessions.values) {
      try {
        await session.chat.close();
        session.isActive = false;
      } catch (e) {
        debugPrint('ParallelSessionManager: Error closing session: $e');
      }
    }
    _notifyListeners();
  }

  /// Remove a closed session
  void removeSession(String sessionId) {
    _sessions.remove(sessionId);
    _notifyListeners();
  }

  /// Get a specific session
  ChatSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  /// Get the most recently active session
  ChatSession? get mostRecentSession {
    if (_sessions.isEmpty) return null;
    return _sessions.values.reduce(
      (a, b) => a.lastActiveAt.isAfter(b.lastActiveAt) ? a : b,
    );
  }

  /// Get or create a model for inference
  Future<InferenceModel?> _getOrCreateModel(NovaModel model) async {
    try {
      if (!FlutterGemma.hasActiveModel()) {
        return null;
      }

      return await FlutterGemma.getActiveModel(
        maxTokens: _tokenLimitFor(model),
        preferredBackend: PreferredBackend.gpu,
      );
    } catch (e) {
      debugPrint('ParallelSessionManager: Failed to get model: $e');
      return null;
    }
  }

  int _tokenLimitFor(NovaModel model) {
    switch (model) {
      case NovaModel.smollm:
        return 512;
      case NovaModel.fastvlm:
        return 1024;
      case NovaModel.gemma3_1b:
        return 2048;
      case NovaModel.gemma4E2b:
        return 4096;
    }
  }

  void _notifyListeners() {
    _sessionsController.add(sessions);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await closeAllSessions();
    await _sessionsController.close();
  }
}

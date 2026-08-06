import 'dart:convert';
import 'dart:typed_data';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Uint8List? imageData;
  final String? modelName;
  final bool isStreaming;
  final bool isError;

  /// True when the user stopped generation; UI may show a stop note without
  /// putting that note into [text] (so reinjection stays clean).
  final bool wasCancelled;
  final String? thinking;
  final String? toolCalls;
  final int? inferenceTimeMs;
  final Map<String, int> reactions;
  final bool isPinned;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.imageData,
    this.modelName,
    this.isStreaming = false,
    this.isError = false,
    this.wasCancelled = false,
    this.thinking,
    this.toolCalls,
    this.inferenceTimeMs,
    this.reactions = const {},
    this.isPinned = false,
  });

  List<Map<String, dynamic>>? _parsedToolCalls;

  List<Map<String, dynamic>>? get parsedToolCalls {
    if (toolCalls == null || toolCalls!.isEmpty) return null;
    if (_parsedToolCalls != null) return _parsedToolCalls;
    try {
      _parsedToolCalls = (jsonDecode(toolCalls!) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } on FormatException {
      _parsedToolCalls = null;
    }

    return _parsedToolCalls;
  }

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    Uint8List? imageData,
    String? modelName,
    bool? isStreaming,
    bool? isError,
    bool? wasCancelled,
    String? thinking,
    String? toolCalls,
    int? inferenceTimeMs,
    Map<String, int>? reactions,
    bool? isPinned,
  }) {
    final hasNewToolCalls = toolCalls != null && toolCalls != this.toolCalls;

    final result = ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      imageData: imageData ?? this.imageData,
      modelName: modelName ?? this.modelName,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      wasCancelled: wasCancelled ?? this.wasCancelled,
      thinking: thinking ?? this.thinking,
      toolCalls: toolCalls ?? this.toolCalls,
      inferenceTimeMs: inferenceTimeMs ?? this.inferenceTimeMs,
      reactions: reactions ?? this.reactions,
      isPinned: isPinned ?? this.isPinned,
    );
    if (hasNewToolCalls) {
      result._parsedToolCalls = null;
    } else {
      result._parsedToolCalls = _parsedToolCalls;
    }

    return result;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    'imageData': imageData != null ? base64Encode(imageData!) : null,
    'modelName': modelName,
    'isStreaming': isStreaming,
    'isError': isError,
    'wasCancelled': wasCancelled,
    'thinking': thinking,
    'toolCalls': toolCalls,
    'inferenceTimeMs': inferenceTimeMs,
    'reactions': reactions,
    'isPinned': isPinned,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    text: json['text'] as String,
    isUser: json['isUser'] as bool,
    timestamp: DateTime.parse(json['timestamp'] as String),
    imageData: json['imageData'] != null
        ? base64Decode(json['imageData'] as String)
        : null,
    modelName: json['modelName'] as String?,
    isStreaming: json['isStreaming'] as bool? ?? false,
    isError: json['isError'] as bool? ?? false,
    wasCancelled: json['wasCancelled'] as bool? ?? false,
    thinking: json['thinking'] as String?,
    toolCalls: json['toolCalls'] as String?,
    inferenceTimeMs: json['inferenceTimeMs'] as int?,
    reactions: json['reactions'] != null
        ? Map<String, int>.from(json['reactions'] as Map)
        : const {},
    isPinned: json['isPinned'] as bool? ?? false,
  );
}

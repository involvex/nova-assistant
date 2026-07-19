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
  });

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
  }) {
    return ChatMessage(
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
    );
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
  );
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Uint8List? imageData;
  final String? modelName;
  final bool isStreaming;
  final bool isError;
  final String? thinking;
  final String? toolCalls;
  final int? inferenceTimeMs;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.imageData,
    this.modelName,
    this.isStreaming = false,
    this.isError = false,
    this.thinking,
    this.toolCalls,
    this.inferenceTimeMs,
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
    String? thinking,
    String? toolCalls,
    int? inferenceTimeMs,
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
      thinking: thinking ?? this.thinking,
      toolCalls: toolCalls ?? this.toolCalls,
      inferenceTimeMs: inferenceTimeMs ?? this.inferenceTimeMs,
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
    'thinking': thinking,
    'toolCalls': toolCalls,
    'inferenceTimeMs': inferenceTimeMs,
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
    thinking: json['thinking'] as String?,
    toolCalls: json['toolCalls'] as String?,
    inferenceTimeMs: json['inferenceTimeMs'] as int?,
  );
}

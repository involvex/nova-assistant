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

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.imageData,
    this.modelName,
    this.isStreaming = false,
    this.isError = false,
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
    );
  }
}

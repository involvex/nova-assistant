import 'package:uuid/uuid.dart';

import 'chat_message.dart';

class Conversation {
  final String id;
  final String? title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    String? id,
    this.title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  String get previewTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final firstUserMessage = messages.where((m) => m.isUser).firstOrNull;
    if (firstUserMessage != null) {
      final text = firstUserMessage.text;
      return text.length > 50 ? '${text.substring(0, 50)}...' : text;
    }
    return 'New conversation';
  }

  String get lastMessageSnippet {
    if (messages.isEmpty) return 'No messages yet';
    final lastMsg = messages.last;
    final text = lastMsg.text;
    return text.length > 60 ? '${text.substring(0, 60)}...' : text;
  }

  int get messageCount => messages.length;

  bool get isEmpty => messages.isEmpty;

  Conversation copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    title: json['title'] as String?,
    messages: (json['messages'] as List<dynamic>)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

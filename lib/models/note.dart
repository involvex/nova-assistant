class Note {
  final String id;
  String title;
  String content;
  List<String> tags;
  DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;

  Note({
    required this.id,
    required this.title,
    required this.content,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isPinned = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tags = tags ?? [];

  Note copyWith({
    String? title,
    String? content,
    List<String>? tags,
    bool? isPinned,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isPinned': isPinned,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isPinned: json['isPinned'] as bool? ?? false,
      );
}

/// Single memory record shared by session + persistent stores.
class MemoryEntry {
  MemoryEntry({
    required this.key,
    required this.content,
    this.scope = 'session',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String key;
  final String content;
  final String scope;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'content': content,
      'scope': scope,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class PromptPreset {
  final String id;
  String name;
  String prompt;
  String? description;
  String? category;
  DateTime createdAt;
  DateTime updatedAt;
  int useCount;

  PromptPreset({
    required this.id,
    required this.name,
    required this.prompt,
    this.description,
    this.category,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.useCount = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  PromptPreset copyWith({
    String? name,
    String? prompt,
    String? description,
    String? category,
    int? useCount,
  }) {
    return PromptPreset(
      id: id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      description: description ?? this.description,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      useCount: useCount ?? this.useCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'description': description,
    'category': category,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'useCount': useCount,
  };

  factory PromptPreset.fromJson(Map<String, dynamic> json) => PromptPreset(
    id: json['id'] as String,
    name: json['name'] as String,
    prompt: json['prompt'] as String,
    description: json['description'] as String?,
    category: json['category'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    useCount: json['useCount'] as int? ?? 0,
  );
}

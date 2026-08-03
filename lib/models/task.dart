enum TaskPriority { low, medium, high }

enum TaskStatus { pending, inProgress, completed, cancelled, archived }

class Task {
  final String id;
  String title;
  String? description;
  TaskPriority priority;
  TaskStatus status;
  DateTime createdAt;
  DateTime? dueDate;
  DateTime? completedAt;
  List<String> tags;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    DateTime? createdAt,
    this.dueDate,
    this.completedAt,
    List<String>? tags,
  }) : createdAt = createdAt ?? DateTime.now(),
       tags = tags ?? [];

  bool get isOverdue {
    if (dueDate == null || status == TaskStatus.completed) return false;

    return DateTime.now().isAfter(dueDate!);
  }

  bool get isPending =>
      status == TaskStatus.pending || status == TaskStatus.inProgress;

  bool get canEdit => status != TaskStatus.cancelled;

  bool get canArchive => status == TaskStatus.completed && !isArchived;

  bool get canRestore => status == TaskStatus.cancelled;

  Task edit({
    String? title,
    String? description,
    TaskPriority? priority,
    TaskStatus? status,
    DateTime? dueDate,
    DateTime? completedAt,
    List<String>? tags,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      tags: tags ?? this.tags,
    );
  }

  Task copyWith({
    String? title,
    String? description,
    TaskPriority? priority,
    TaskStatus? status,
    DateTime? dueDate,
    DateTime? completedAt,
    List<String>? tags,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      tags: tags ?? this.tags,
    );
  }

  bool get isArchived => status == TaskStatus.archived;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'priority': priority.name,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'tags': tags,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    priority: TaskPriority.values.firstWhere(
      (p) => p.name == json['priority'],
      orElse: () => TaskPriority.medium,
    ),
    status: TaskStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => TaskStatus.pending,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    dueDate: json['dueDate'] != null
        ? DateTime.parse(json['dueDate'] as String)
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null,
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}

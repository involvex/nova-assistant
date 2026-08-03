import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:nova_assistant/models/task.dart';
import 'package:nova_assistant/services/notification_service.dart';

List<Task> _parseTasksFromJson(String json) {
  final list = jsonDecode(json) as List<dynamic>;
  return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
}

class TaskService {
  static TaskService? _instance;
  static TaskService get instance => _instance ??= TaskService._();
  TaskService._();

  static const _prefsKey = 'nova_tasks';
  static const _uuid = Uuid();

  StreamController<List<Task>> _tasksController =
      StreamController<List<Task>>.broadcast();
  Stream<List<Task>> get tasksStream => _tasksController.stream;

  List<Task> _tasks = [];

  List<Task> get tasks => List.unmodifiable(_tasks);

  List<Task> get pendingTasks => _tasks.where((t) => t.isPending).toList();

  List<Task> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();

  List<Task> get overdueTasks => _tasks.where((t) => t.isOverdue).toList();

  Future<void> initialize() async {
    if (_tasksController.isClosed) {
      _tasksController = StreamController<List<Task>>.broadcast();
    }
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json != null && json.isNotEmpty) {
      try {
        _tasks = await compute(_parseTasksFromJson, json);
      } catch (_) {
        _tasks = [];
      }
    }
    _notifyListeners();
  }

  Future<Task> createTask({
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.medium,
    DateTime? dueDate,
    List<String> tags = const [],
  }) async {
    final task = Task(
      id: _uuid.v4(),
      title: title,
      description: description,
      priority: priority,
      dueDate: dueDate,
      tags: tags,
    );
    _tasks.add(task);
    await _save();
    _notifyListeners();

    if (task.dueDate != null) {
      _scheduleReminder(task);
    }

    return task;
  }

  void _scheduleReminder(Task task) {
    final notifService = NotificationService.instance;
    final reminderTime = task.dueDate!.subtract(const Duration(hours: 1));
    if (reminderTime.isAfter(DateTime.now())) {
      notifService.scheduleTaskReminder(
        id: notifService.notificationIdForTask(task.id),
        title: 'Task due soon',
        body: '${task.title} is due in 1 hour',
        scheduledTime: reminderTime,
        taskId: task.id,
      );
    }
  }

  Future<void> updateTask(Task task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      await _save();
      _notifyListeners();
    }
  }

  Future<void> completeTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        status: TaskStatus.completed,
        completedAt: DateTime.now(),
      );
      await _save();
      _notifyListeners();

      NotificationService.instance.cancelNotification(
        NotificationService.instance.notificationIdForTask(taskId),
      );
    }
  }

  Future<void> deleteTask(String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
    await _save();
    _notifyListeners();

    NotificationService.instance.cancelNotification(
      NotificationService.instance.notificationIdForTask(taskId),
    );
  }

  Future<void> editTask(Task task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      await _save();
      _notifyListeners();

      // Reschedule reminder if due date changed
      if (task.dueDate != null) {
        _scheduleReminder(task);
      }
    }
  }

  Future<void> archiveTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(status: TaskStatus.archived);
      await _save();
      _notifyListeners();

      NotificationService.instance.cancelNotification(
        NotificationService.instance.notificationIdForTask(taskId),
      );
    }
  }

  Task? findTaskById(String taskId) {
    try {
      return _tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  Task? findTaskByTitle(String query) {
    final lower = query.toLowerCase();
    // Try exact match first
    for (final task in _tasks) {
      if (task.title.toLowerCase() == lower) return task;
    }
    // Fuzzy match
    for (final task in _tasks) {
      if (task.title.toLowerCase().contains(lower)) return task;
    }
    return null;
  }

  List<Task> searchTasks(String query) {
    final lower = query.toLowerCase();
    return _tasks.where((t) {
      return t.title.toLowerCase().contains(lower) ||
          (t.description?.toLowerCase().contains(lower) ?? false) ||
          t.tags.any((tag) => tag.toLowerCase().contains(lower));
    }).toList();
  }

  /// Handle tool calls from the AI model.
  Future<Map<String, dynamic>> executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    switch (toolName) {
      case 'create_task':
        return _handleCreateTask(args);
      case 'list_tasks':
        return _handleListTasks(args);
      case 'complete_task':
        return _handleCompleteTask(args);
      case 'edit_task':
        return _handleEditTask(args);
      case 'archive_task':
        return _handleArchiveTask(args);
      case 'restore_task':
        return _handleRestoreTask(args);
      default:
        return {'success': false, 'error': 'Unknown task tool: $toolName'};
    }
  }

  Future<Map<String, dynamic>> _handleCreateTask(
    Map<String, dynamic> args,
  ) async {
    final title = args['title'] as String?;
    if (title == null || title.isEmpty) {
      return {'success': false, 'error': 'Title is required'};
    }

    final priorityStr = args['priority'] as String?;
    final priority = TaskPriority.values.firstWhere(
      (p) => p.name == priorityStr,
      orElse: () => TaskPriority.medium,
    );

    DateTime? dueDate;
    if (args['due_date'] != null) {
      try {
        dueDate = DateTime.parse(args['due_date'] as String);
      } catch (e) {
        debugPrint(
          'TaskService.createTask: invalid due_date format: ${args['due_date']}',
        );
      }
    }

    final tagsStr = args['tags'] as String?;
    final tags = tagsStr != null
        ? tagsStr.split(',').map((t) => t.trim()).toList()
        : <String>[];

    final task = await createTask(
      title: title,
      description: args['description'] as String?,
      priority: priority,
      dueDate: dueDate,
      tags: tags,
    );

    return {
      'success': true,
      'taskId': task.id,
      'title': task.title,
      'message': 'Task created: ${task.title}',
    };
  }

  Future<Map<String, dynamic>> _handleListTasks(
    Map<String, dynamic> args,
  ) async {
    final active = pendingTasks;
    if (active.isEmpty) {
      return {
        'success': true,
        'message': 'No pending tasks',
        'tasks': <Map<String, dynamic>>[],
      };
    }

    return {
      'success': true,
      'count': active.length,
      'tasks': active
          .map(
            (t) => {
              'id': t.id,
              'title': t.title,
              'priority': t.priority.name,
              'dueDate': t.dueDate?.toIso8601String(),
              'isOverdue': t.isOverdue,
            },
          )
          .toList(),
      'message': '${active.length} pending task(s)',
    };
  }

  Future<Map<String, dynamic>> _handleCompleteTask(
    Map<String, dynamic> args,
  ) async {
    final titleQuery = args['title'] as String?;
    if (titleQuery == null || titleQuery.isEmpty) {
      return {'success': false, 'error': 'Task title is required'};
    }

    final task = findTaskByTitle(titleQuery);
    if (task == null) {
      return {'success': false, 'error': 'Task not found: $titleQuery'};
    }

    await completeTask(task.id);
    return {'success': true, 'message': 'Task completed: ${task.title}'};
  }

  Future<Map<String, dynamic>> _handleEditTask(
    Map<String, dynamic> args,
  ) async {
    final taskId = args['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      return {'success': false, 'error': 'Task ID is required'};
    }

    final task = findTaskById(taskId);
    if (task == null) {
      return {'success': false, 'error': 'Task not found: $taskId'};
    }

    final title = args['title'] as String?;
    final description = args['description'] as String?;
    final priorityStr = args['priority'] as String?;
    final statusStr = args['status'] as String?;
    final dueDateStr = args['due_date'] as String?;

    TaskPriority? priority;
    if (priorityStr != null) {
      priority = TaskPriority.values.firstWhere(
        (p) => p.name == priorityStr,
        orElse: () => task.priority,
      );
    }

    TaskStatus? status;
    if (statusStr != null) {
      status = TaskStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => task.status,
      );
    }

    DateTime? dueDate;
    if (dueDateStr != null) {
      try {
        dueDate = DateTime.parse(dueDateStr);
      } catch (e) {
        return {'success': false, 'error': 'Invalid due_date format'};
      }
    }

    final tagsStr = args['tags'] as String?;
    final tags = tagsStr != null
        ? tagsStr.split(',').map((t) => t.trim()).toList()
        : task.tags;

    final updatedTask = task.edit(
      title: title,
      description: description,
      priority: priority,
      status: status,
      dueDate: dueDate,
      tags: tags,
    );

    await editTask(updatedTask);
    return {
      'success': true,
      'taskId': updatedTask.id,
      'title': updatedTask.title,
      'message': 'Task updated: ${updatedTask.title}',
    };
  }

  Future<Map<String, dynamic>> _handleArchiveTask(
    Map<String, dynamic> args,
  ) async {
    final taskId = args['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      return {'success': false, 'error': 'Task ID is required'};
    }

    final task = findTaskById(taskId);
    if (task == null) {
      return {'success': false, 'error': 'Task not found: $taskId'};
    }

    if (!task.canArchive) {
      return {'success': false, 'error': 'Task cannot be archived'};
    }

    await archiveTask(task.id);
    return {'success': true, 'message': 'Task archived: ${task.title}'};
  }

  Future<Map<String, dynamic>> _handleRestoreTask(
    Map<String, dynamic> args,
  ) async {
    final taskId = args['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      return {'success': false, 'error': 'Task ID is required'};
    }

    final task = findTaskById(taskId);
    if (task == null) {
      return {'success': false, 'error': 'Task not found: $taskId'};
    }

    if (!task.canRestore) {
      return {'success': false, 'error': 'Task cannot be restored'};
    }

    await editTask(task.edit(status: TaskStatus.pending));
    return {'success': true, 'message': 'Task restored: ${task.title}'};
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_prefsKey, json);
  }

  void _notifyListeners() {
    _tasksController.add(tasks);
  }

  Future<void> dispose() async {
    await _tasksController.close();
  }

  static void reset() {
    _instance = null;
  }
}

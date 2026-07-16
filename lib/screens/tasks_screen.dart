import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nova_assistant/models/task.dart';
import 'package:nova_assistant/services/task_service.dart';
import 'package:nova_assistant/services/export_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _taskService = TaskService.instance;
  List<Task> _tasks = [];
  String _filter = 'all';
  String _sortBy = 'created';
  StreamSubscription<List<Task>>? _tasksSub;

  @override
  void initState() {
    super.initState();
    _tasks = _taskService.tasks;
    _tasksSub = _taskService.tasksStream.listen((tasks) {
      if (mounted) setState(() => _tasks = tasks);
    });
  }

  @override
  void dispose() {
    _tasksSub?.cancel();
    super.dispose();
  }

  List<Task> get _filteredTasks {
    List<Task> tasks;
    switch (_filter) {
      case 'pending':
        tasks = _taskService.pendingTasks;
        break;
      case 'completed':
        tasks = _taskService.completedTasks;
        break;
      case 'overdue':
        tasks = _taskService.overdueTasks;
        break;
      default:
        tasks = _tasks;
    }

    final sorted = List<Task>.from(tasks);
    switch (_sortBy) {
      case 'priority':
        sorted.sort((a, b) => a.priority.index.compareTo(b.priority.index));
        break;
      case 'dueDate':
        sorted.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;
      case 'title':
        sorted.sort((a, b) => a.title.compareTo(b.title));
        break;
      default: // 'created'
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Tasks'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _sortBy = value),
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'created', child: Text('Date created')),
              const PopupMenuItem(value: 'dueDate', child: Text('Due date')),
              const PopupMenuItem(value: 'priority', child: Text('Priority')),
              const PopupMenuItem(value: 'title', child: Text('Title')),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _filter = value),
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(value: 'completed', child: Text('Completed')),
              const PopupMenuItem(value: 'overdue', child: Text('Overdue')),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              ExportService.instance.shareTasks(format: value);
            },
            icon: const Icon(Icons.share),
            tooltip: 'Export tasks',
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'json', child: Text('Export as JSON')),
              const PopupMenuItem(value: 'text', child: Text('Export as text')),
            ],
          ),
        ],
      ),
      body: _filteredTasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_alt, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text(
                    _filter == 'all' ? 'No tasks yet' : 'No $_filter tasks',
                    style: TextStyle(color: Colors.grey[500], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ask Nova to create a task, or tap +',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _filteredTasks.length,
              itemBuilder: (context, index) => _TaskCard(
                task: _filteredTasks[index],
                onComplete: () =>
                    _taskService.completeTask(_filteredTasks[index].id),
                onDelete: () =>
                    _taskService.deleteTask(_filteredTasks[index].id),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: const Color(0xFF6C63FF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showCreateDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final tagController = TextEditingController();
    TaskPriority priority = TaskPriority.medium;
    DateTime? dueDate;
    List<String> tags = [];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New Task',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Task title',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Description (optional)',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: tagController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      onSubmitted: (value) {
                        final tag = value.trim();
                        if (tag.isNotEmpty && !tags.contains(tag)) {
                          setModalState(() {
                            tags = [...tags, tag];
                            tagController.clear();
                          });
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Add tag...',
                        hintStyle:
                            TextStyle(color: Colors.grey[600], fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0D0D1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      final tag = tagController.text.trim();
                      if (tag.isNotEmpty && !tags.contains(tag)) {
                        setModalState(() {
                          tags = [...tags, tag];
                          tagController.clear();
                        });
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    color: const Color(0xFF6C63FF),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags
                      .map(
                        (tag) => Chip(
                          label:
                              Text(tag, style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              const Color(0xFF6C63FF).withValues(alpha: 0.15),
                          labelStyle: const TextStyle(color: Color(0xFF6C63FF)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => setModalState(() {
                            tags = tags.where((t) => t != tag).toList();
                          }),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _PriorityChip(
                    label: 'Low',
                    color: Colors.green,
                    selected: priority == TaskPriority.low,
                    onTap: () =>
                        setModalState(() => priority = TaskPriority.low),
                  ),
                  const SizedBox(width: 8),
                  _PriorityChip(
                    label: 'Med',
                    color: Colors.orange,
                    selected: priority == TaskPriority.medium,
                    onTap: () =>
                        setModalState(() => priority = TaskPriority.medium),
                  ),
                  const SizedBox(width: 8),
                  _PriorityChip(
                    label: 'High',
                    color: Colors.red,
                    selected: priority == TaskPriority.high,
                    onTap: () =>
                        setModalState(() => priority = TaskPriority.high),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365),
                        ),
                      );
                      if (picked != null) {
                        setModalState(() => dueDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      dueDate != null
                          ? '${dueDate!.month}/${dueDate!.day}'
                          : 'Due date',
                      style: TextStyle(
                        color: dueDate != null
                            ? const Color(0xFF6C63FF)
                            : Colors.grey[500],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (titleController.text.isNotEmpty) {
                    _taskService.createTask(
                      title: titleController.text.trim(),
                      description: descController.text.trim().isEmpty
                          ? null
                          : descController.text.trim(),
                      priority: priority,
                      dueDate: dueDate,
                      tags: tags,
                    );
                    Navigator.pop(ctx);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Create Task'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == TaskStatus.completed;
    final isOverdue = task.isOverdue;

    return Dismissible(
      key: Key(task.id),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted
                ? Colors.green.withValues(alpha: 0.3)
                : isOverdue
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: isCompleted ? null : onComplete,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted ? Colors.green : Colors.transparent,
                  border: Border.all(
                    color: isCompleted
                        ? Colors.green
                        : task.priority == TaskPriority.high
                            ? Colors.red
                            : task.priority == TaskPriority.low
                                ? Colors.green
                                : Colors.orange,
                    width: 2,
                  ),
                ),
                child: isCompleted
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (task.description != null &&
                      task.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description!,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (task.dueDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${task.dueDate!.year}-${task.dueDate!.month.toString().padLeft(2, '0')}-${task.dueDate!.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? Colors.red : Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (task.tags.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.tags.first,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PriorityChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.grey[700]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? color : Colors.grey[500],
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

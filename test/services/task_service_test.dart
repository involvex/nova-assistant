import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/task.dart';
import 'package:nova_assistant/services/task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TaskService service;

  setUp(() async {
    TaskService.reset();
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    service = TaskService.instance;
    await service.initialize();
  });

  tearDown(() async {
    await service.dispose();
  });

  group('TaskService', () {
    test('initializes with empty tasks list', () {
      expect(service.tasks, isEmpty);
    });

    group('createTask', () {
      test('creates a task with correct fields', () async {
        final task = await service.createTask(
          title: 'Test Task',
          description: 'A test description',
          priority: TaskPriority.high,
        );

        expect(task.title, 'Test Task');
        expect(task.description, 'A test description');
        expect(task.priority, TaskPriority.high);
        expect(task.status, TaskStatus.pending);
      });

      test('task appears in tasks list', () async {
        await service.createTask(title: 'Task 1');
        expect(service.tasks.length, 1);
        expect(service.tasks[0].title, 'Task 1');
      });
    });

    group('completeTask', () {
      test('marks task as completed', () async {
        final task = await service.createTask(title: 'Complete me');
        await service.completeTask(task.id);

        final updated = service.tasks.firstWhere((t) => t.id == task.id);
        expect(updated.status, TaskStatus.completed);
        expect(updated.completedAt, isNotNull);
      });
    });

    group('deleteTask', () {
      test('removes task from list', () async {
        final task = await service.createTask(title: 'Delete me');
        expect(service.tasks.length, 1);

        await service.deleteTask(task.id);
        expect(service.tasks, isEmpty);
      });
    });

    group('querying', () {
      test('pendingTasks returns only pending', () async {
        final t1 = await service.createTask(title: 'Pending');
        final t2 = await service.createTask(title: 'Done');
        await service.completeTask(t2.id);

        expect(service.pendingTasks.length, 1);
        expect(service.pendingTasks[0].id, t1.id);
      });

      test('completedTasks returns only completed', () async {
        await service.createTask(title: 'Pending');
        final t2 = await service.createTask(title: 'Done');
        await service.completeTask(t2.id);

        expect(service.completedTasks.length, 1);
        expect(service.completedTasks[0].id, t2.id);
      });
    });

    group('persistence', () {
      test('tasks survive reinitialize', () async {
        await service.createTask(title: 'Persist me');
        await service.dispose();

        final service2 = TaskService.instance;
        await service2.initialize();
        expect(service2.tasks.length, 1);
        expect(service2.tasks[0].title, 'Persist me');
      });
    });

    group('executeTool', () {
      test('create_task creates a task', () async {
        final result = await service.executeTool('create_task', {
          'title': 'AI Task',
          'priority': 'low',
        });

        expect(result['success'], true);
        expect(service.tasks.length, 1);
        expect(service.tasks[0].title, 'AI Task');
      });

      test('list_tasks returns tasks', () async {
        await service.createTask(title: 'List me');
        final result = await service.executeTool('list_tasks', {});

        expect(result['success'], true);
        expect(result['count'], 1);
      });

      test('complete_task marks task done', () async {
        await service.createTask(title: 'Finish');
        final result = await service.executeTool('complete_task', {
          'title': 'Finish',
        });

        expect(result['success'], true);
        expect(service.tasks[0].status, TaskStatus.completed);
      });
    });
  });
}

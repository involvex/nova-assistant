import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'package:nova_assistant/models/task.dart';
import 'package:nova_assistant/models/note.dart';
import 'package:nova_assistant/services/task_service.dart';
import 'package:nova_assistant/services/note_service.dart';
import 'package:nova_assistant/services/memory_service.dart';

class WidgetService {
  static WidgetService? _instance;
  static WidgetService get instance => _instance ??= WidgetService._();
  WidgetService._();

  static const _appGroupId = 'dev.nova.assistant.widget';
  static const _widgetChannel = 'dev.nova.assistant/widget';

  static const _tasksCountKey = 'tasks_count';
  static const _notesCountKey = 'notes_count';
  static const _memoryCountKey = 'memory_count';
  static const _modelStatusKey = 'model_status';

  StreamSubscription<List<Task>>? _tasksSubscription;
  StreamSubscription<List<Note>>? _notesSubscription;
  StreamSubscription<dynamic>? _widgetChannelSubscription;

  final _widgetActionController = StreamController<String>.broadcast();
  Stream<String> get widgetActionStream => _widgetActionController.stream;

  Future<void> initialize() async {
    await HomeWidget.setAppGroupId(_appGroupId);

    _setupWidgetChannelListener();
    await _updateAllStats();
    await _updateModelStatus('Ready');

    _tasksSubscription = TaskService.instance.tasksStream.listen((_) {
      updateStatsWidget();
    });

    _notesSubscription = NoteService.instance.notesStream.listen((_) {
      updateStatsWidget();
    });
  }

  Future<void> _setupWidgetChannelListener() async {
    try {
      const eventChannel = EventChannel(_widgetChannel);
      _widgetChannelSubscription = eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is String) {
            _widgetActionController.add(event);
          }
        },
        onError: (Object error) {
          debugPrint('Widget channel error: $error');
        },
      );

      const methodChannel = MethodChannel(_widgetChannel);
      final initialAction = await methodChannel.invokeMethod<String>(
        'getInitialWidgetAction',
      );
      if (initialAction != null) {
        _widgetActionController.add(initialAction);
      }
    } catch (e) {
      debugPrint('Widget channel setup error: $e');
    }
  }

  Future<int> _getMemoryCount() async {
    try {
      final customMemories = await MemoryService.getCustomMemories();
      return customMemories.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _updateAllStats() async {
    final tasksCount = TaskService.instance.tasks.length;
    final notesCount = NoteService.instance.notes.length;
    final memoryCount = await _getMemoryCount();

    await _saveWidgetData({
      _tasksCountKey: tasksCount,
      _notesCountKey: notesCount,
      _memoryCountKey: memoryCount,
    });
  }

  Future<void> updateStatsWidget({
    int? tasksCount,
    int? notesCount,
    int? memoryCount,
  }) async {
    final actualTasksCount = tasksCount ?? TaskService.instance.tasks.length;
    final actualNotesCount = notesCount ?? NoteService.instance.notes.length;
    final actualMemoryCount = memoryCount ?? await _getMemoryCount();

    await _saveWidgetData({
      _tasksCountKey: actualTasksCount,
      _notesCountKey: actualNotesCount,
      _memoryCountKey: actualMemoryCount,
    });

    try {
      await HomeWidget.updateWidget(
        androidName: 'StatsWidgetProvider',
        iOSName: 'StatsWidget',
      );
    } catch (e) {
      debugPrint('WidgetService.updateStatsWidget error: $e');
    }
  }

  Future<void> _updateModelStatus(String status) async {
    await HomeWidget.saveWidgetData<String>(_modelStatusKey, status);
    try {
      await HomeWidget.updateWidget(
        androidName: 'AtAGlanceWidgetProvider',
        iOSName: 'AtAGlanceWidget',
      );
    } catch (e) {
      debugPrint('WidgetService._updateModelStatus error: $e');
    }
  }

  Future<void> updateAllWidgets() async {
    await _updateAllStats();
    try {
      await Future.wait([
        HomeWidget.updateWidget(
          androidName: 'QuickActionsWidgetProvider',
          iOSName: 'QuickActionsWidget',
        ),
        HomeWidget.updateWidget(
          androidName: 'AtAGlanceWidgetProvider',
          iOSName: 'AtAGlanceWidget',
        ),
        HomeWidget.updateWidget(
          androidName: 'StatsWidgetProvider',
          iOSName: 'StatsWidget',
        ),
      ]);
    } catch (e) {
      debugPrint('WidgetService.updateAllWidgets error: $e');
    }
  }

  Future<void> _saveWidgetData(Map<String, int> data) async {
    try {
      await Future.forEach(data.entries, (entry) async {
        await HomeWidget.saveWidgetData<int>(entry.key, entry.value);
      });
    } catch (e) {
      debugPrint('WidgetService._saveWidgetData error: $e');
    }
  }

  void dispose() {
    _tasksSubscription?.cancel();
    _notesSubscription?.cancel();
    _widgetChannelSubscription?.cancel();
    _widgetActionController.close();
  }

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}

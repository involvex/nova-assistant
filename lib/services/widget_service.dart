import 'dart:async';

import 'package:flutter/foundation.dart';
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

  static const _tasksCountKey = 'tasks_count';
  static const _notesCountKey = 'notes_count';
  static const _memoryCountKey = 'memory_count';
  static const _modelStatusKey = 'model_status';
  static const _widgetActionKey = 'home_widget_action';

  StreamSubscription<List<Task>>? _tasksSubscription;
  StreamSubscription<List<Note>>? _notesSubscription;

  final _widgetActionController = StreamController<String>.broadcast();
  Stream<String> get widgetActionStream => _widgetActionController.stream;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await HomeWidget.setAppGroupId(_appGroupId);

    _listenForWidgetActions();

    await _updateAllStats();
    await _updateModelStatus('Ready');

    _tasksSubscription = TaskService.instance.tasksStream.listen((_) {
      updateStatsWidget();
    });

    _notesSubscription = NoteService.instance.notesStream.listen((_) {
      updateStatsWidget();
    });
  }

  bool _isSystemAction(String action) {
    return action.startsWith('android.') ||
        action == 'android.appwidget.action.APPWIDGET_UPDATE' ||
        action.startsWith('com.android.') ||
        action.startsWith('com.google.') ||
        action.isEmpty;
  }

  void _listenForWidgetActions() {
    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final action = await HomeWidget.getWidgetData<String>(_widgetActionKey);
        if (action != null && action.isNotEmpty && !_isSystemAction(action)) {
          _widgetActionController.add(action);
          await HomeWidget.saveWidgetData<String>(_widgetActionKey, '');
        } else if (action != null &&
            action.isNotEmpty &&
            _isSystemAction(action)) {
          await HomeWidget.saveWidgetData<String>(_widgetActionKey, '');
        }
      } catch (_) {}
    });
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

  Future<void> updateStatsWidget() async {
    final actualTasksCount = TaskService.instance.tasks.length;
    final actualNotesCount = NoteService.instance.notes.length;
    final actualMemoryCount = await _getMemoryCount();

    await _saveWidgetData({
      _tasksCountKey: actualTasksCount,
      _notesCountKey: actualNotesCount,
      _memoryCountKey: actualMemoryCount,
    });

    try {
      await HomeWidget.updateWidget(
        androidName: 'widget.StatsWidgetProvider',
        iOSName: 'StatsWidget',
      );
    } catch (e) {
      debugPrint('WidgetService.updateStatsWidget error: $e');
    }
  }

  Future<void> _updateModelStatus(String status) async {
    try {
      await HomeWidget.saveWidgetData<String>(_modelStatusKey, status);
      await HomeWidget.updateWidget(
        androidName: 'widget.AtAGlanceWidgetProvider',
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
          androidName: 'widget.QuickActionsWidgetProvider',
          iOSName: 'QuickActionsWidget',
        ),
        HomeWidget.updateWidget(
          androidName: 'widget.AtAGlanceWidgetProvider',
          iOSName: 'AtAGlanceWidget',
        ),
        HomeWidget.updateWidget(
          androidName: 'widget.StatsWidgetProvider',
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
    _widgetActionController.close();
  }

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}

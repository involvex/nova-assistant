import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Payload actions mirrored from home-widget deep links.
class NotificationAction {
  static const openTasks = 'ACTION_OPEN_TASKS';
  static const openChat = 'ACTION_NEW_CHAT';
  static const askNova = 'ACTION_QUICK_ASK';
  static const openTaskPrefix = 'ACTION_OPEN_TASK:';

  static String openTask(String taskId) => '$openTaskPrefix$taskId';
}

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _actionController = StreamController<String>.broadcast();
  bool _initialized = false;

  Stream<String> get actionStream => _actionController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _actionController.add(payload);
      }
    }

    _initialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    // Action buttons use actionId; body tap uses payload.
    final action = response.actionId;
    if (action != null && action.isNotEmpty) {
      _actionController.add(action);

      return;
    }
    _actionController.add(payload);
  }

  Future<bool> requestPermission() async {
    if (await Permission.notification.isGranted) return true;

    final status = await Permission.notification.request();

    return status.isGranted;
  }

  Future<void> scheduleTaskReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? taskId,
  }) async {
    if (!_initialized) return;
    if (scheduledTime.isBefore(DateTime.now())) return;

    final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);
    final payload = taskId != null
        ? NotificationAction.openTask(taskId)
        : NotificationAction.openTasks;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDateTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'nova_task_reminders',
          'Task Reminders',
          channelDescription: 'Reminders for tasks with due dates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              NotificationAction.openTasks,
              'Open tasks',
            ),
            const AndroidNotificationAction(
              NotificationAction.askNova,
              'Ask Nova',
            ),
            const AndroidNotificationAction(
              NotificationAction.openChat,
              'Open chat',
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  int notificationIdForTask(String taskId) {
    return taskId.hashCode & 0x7FFFFFFF;
  }

  Future<void> dispose() async {
    await _actionController.close();
  }
}

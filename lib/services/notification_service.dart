import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap — could navigate to task detail
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
  }) async {
    if (!_initialized) return;
    if (scheduledTime.isBefore(DateTime.now())) return;

    final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDateTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nova_task_reminders',
          'Task Reminders',
          channelDescription: 'Reminders for tasks with due dates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
}

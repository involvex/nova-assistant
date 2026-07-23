import 'dart:async';

import 'package:flutter/services.dart';
import 'package:nova_assistant/models/tool_progress.dart';
import 'package:nova_assistant/services/shizuku_service.dart';

class ToolExecutorService {
  static const _channel = MethodChannel('dev.nova.assistant/tools');
  static const _progressChannel = EventChannel(
    'dev.nova.assistant/tools_progress',
  );

  static ToolExecutorService? _instance;
  static ToolExecutorService get instance =>
      _instance ??= ToolExecutorService._();

  ToolExecutorService._();

  Stream<ToolProgress>? _progressStream;

  /// Stream of tool execution progress events from the native side.
  Stream<ToolProgress> get onProgress {
    _progressStream ??= _progressChannel
        .receiveBroadcastStream()
        .where((event) => event != null)
        .map(
          (event) =>
              ToolProgress.fromMap(Map<String, dynamic>.from(event as Map)),
        );

    return _progressStream!;
  }

  Future<Map<String, dynamic>> executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    if (toolName == 'force_stop_app') {
      final pkg = args['package']?.toString() ?? '';
      return ShizukuService.instance.forceStopApp(pkg);
    }

    try {
      final result = await _channel.invokeMethod(toolName, args);
      if (result is Map) {
        return _convertResultDynamicToListInt(
          Map<String, dynamic>.from(result),
        );
      }

      return {'success': true, 'result': result};
    } on PlatformException catch (e) {
      return {'success': false, 'error': e.message ?? 'Platform error'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Map<String, dynamic> _convertResultDynamicToListInt(
    Map<String, dynamic> map,
  ) {
    return map.map((key, value) {
      if (value is List<dynamic>) {
        final converted = value.map((e) {
          if (e is int) return e;
          if (e is double) return e.toInt();

          return e;
        }).toList();

        return MapEntry(key, converted);
      }

      return MapEntry(key, value);
    });
  }

  Future<Map<String, dynamic>> getTime() async {
    return executeTool('get_time', {});
  }

  Future<Map<String, dynamic>> setAlarm(
    int hour,
    int minute,
    String message,
  ) async {
    return executeTool('set_alarm', {
      'hour': hour,
      'minute': minute,
      'message': message,
    });
  }

  Future<Map<String, dynamic>> openApp(String package) async {
    return executeTool('open_app', {'package': package});
  }

  Future<Map<String, dynamic>> searchWeb(String query) async {
    return executeTool('search_web', {'query': query});
  }

  Future<Map<String, dynamic>> getWeather(String location) async {
    return executeTool('get_weather', {'location': location});
  }

  Future<Map<String, dynamic>> sendSms(String phone, String message) async {
    return executeTool('send_sms', {'phone': phone, 'message': message});
  }

  Future<Map<String, dynamic>> openSettings() async {
    return executeTool('open_settings', {});
  }

  Future<Uint8List?> takeScreenshot() async {
    final result = await executeTool('take_screenshot', {});
    final data = result['data'];
    if (data != null) {
      if (data is Uint8List) return data;
      if (data is List<int>) return Uint8List.fromList(data);
    }

    return null;
  }
}

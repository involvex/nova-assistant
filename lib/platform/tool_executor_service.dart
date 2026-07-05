import 'package:flutter/services.dart';

class ToolExecutorService {
  static const _channel = MethodChannel('dev.nova.assistant/tools');

  static ToolExecutorService? _instance;
  static ToolExecutorService get instance =>
      _instance ??= ToolExecutorService._();

  ToolExecutorService._();

  Future<Map<String, dynamic>> executeTool(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    try {
      final result = await _channel.invokeMethod(toolName, args);
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {"success": true, "result": result};
    } on PlatformException catch (e) {
      return {"success": false, "error": e.message ?? 'Platform error'};
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
  }

  Future<Map<String, dynamic>> getTime() async {
    return executeTool("get_time", {});
  }

  Future<Map<String, dynamic>> setAlarm(
    int hour,
    int minute,
    String message,
  ) async {
    return executeTool("set_alarm", {
      "hour": hour,
      "minute": minute,
      "message": message,
    });
  }

  Future<Map<String, dynamic>> openApp(String package) async {
    return executeTool("open_app", {"package": package});
  }

  Future<Map<String, dynamic>> searchWeb(String query) async {
    return executeTool("search_web", {"query": query});
  }

  Future<Map<String, dynamic>> getWeather(String location) async {
    return executeTool("get_weather", {"location": location});
  }

  Future<Map<String, dynamic>> sendSms(String phone, String message) async {
    return executeTool("send_sms", {"phone": phone, "message": message});
  }

  Future<Map<String, dynamic>> openSettings() async {
    return executeTool("open_settings", {});
  }

  Future<Uint8List?> takeScreenshot() async {
    final result = await executeTool("take_screenshot", {});
    if (result['success'] == true && result['data'] != null) {
      final data = result['data'];
      if (data is Uint8List) return data;
      if (data is List<int>) return Uint8List.fromList(data);
    }
    return null;
  }
}

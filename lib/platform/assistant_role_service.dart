import 'dart:async';
import 'package:flutter/services.dart';

class AssistantRoleService {
  static const _methodChannel = MethodChannel('dev.nova.assistant/main');
  static const _eventChannel = EventChannel('dev.nova.assistant/main_events');

  static AssistantRoleService? _instance;
  static AssistantRoleService get instance =>
      _instance ??= AssistantRoleService._();

  AssistantRoleService._();

  Stream<Map<String, dynamic>> get onAssistantRoleChanged {
    return _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }

  Future<bool> isAssistantRoleHeld() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isAssistantRoleHeld',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestAssistantRole() async {
    try {
      await _methodChannel.invokeMethod<void>('requestAssistantRole');
    } on PlatformException catch (e) {
      throw Exception('Failed to request assistant role: ${e.message}');
    }
  }
}

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/services/mcp_service.dart';

class NovaTools {
  static List<Tool> get all => [
        ..._builtInTools,
        ...McpService.instance.enabledTools,
      ];

  static final List<Tool> _builtInTools = [
    getTime,
    setAlarm,
    cancelAlarm,
    openApp,
    searchWeb,
    getWeather,
    sendSms,
    openSettings,
    takeScreenshot,
  ];

  static final Tool getTime = Tool(
    name: 'get_time',
    description: 'Get the current time, date, and day of the week. '
        'Use this ONLY when the user explicitly asks for the '
        'current time, date, or what day it is.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );

  static final Tool setAlarm = Tool(
    name: 'set_alarm',
    description: 'Set an alarm on the device. '
        'Use this ONLY when the user explicitly asks to set, '
        'create, or schedule an alarm or timer.',
    parameters: {
      'type': 'object',
      'properties': {
        'hour': {'type': 'integer', 'description': 'Hour (0-23)'},
        'minute': {'type': 'integer', 'description': 'Minute (0-59)'},
        'message': {'type': 'string', 'description': 'Alarm label/message'},
      },
      'required': ['hour', 'minute'],
    },
  );

  static final Tool cancelAlarm = Tool(
    name: 'cancel_alarm',
    description: 'Cancel an existing alarm on the device. '
        'Use this ONLY when the user explicitly asks to cancel '
        'or remove an existing alarm.',
    parameters: {
      'type': 'object',
      'properties': {
        'hour': {
          'type': 'integer',
          'description': 'Hour of alarm to cancel (0-23)',
        },
        'minute': {
          'type': 'integer',
          'description': 'Minute of alarm to cancel (0-59)',
        },
      },
      'required': ['hour', 'minute'],
    },
  );

  static final Tool openApp = Tool(
    name: 'open_app',
    description: 'Open an application on the device. '
        'Use this ONLY when the user explicitly asks to open '
        'or launch a specific application.',
    parameters: {
      'type': 'object',
      'properties': {
        'package': {
          'type': 'string',
          'description': 'App package name (e.g. com.twitter.android)',
        },
      },
      'required': ['package'],
    },
  );

  static final Tool searchWeb = Tool(
    name: 'search_web',
    description: 'Open a web browser and perform a search. '
        'Use this ONLY when the user explicitly asks to search, '
        'look up, find online, or check the internet for something. '
        'Do NOT use this for general questions, greetings, or '
        'conversations that can be answered from local knowledge.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Search query'},
      },
      'required': ['query'],
    },
  );

  static final Tool getWeather = Tool(
    name: 'get_weather',
    description: 'Get current weather information for a specific location. '
        'Use this ONLY when the user explicitly asks about weather, '
        'temperature, or conditions for a specific place.',
    parameters: {
      'type': 'object',
      'properties': {
        'location': {
          'type': 'string',
          'description': 'City name or "current location"',
        },
      },
    },
  );

  static final Tool sendSms = Tool(
    name: 'send_sms',
    description: 'Send an SMS text message to a phone number. '
        'Use this ONLY when the user explicitly asks to send '
        'a text message or SMS to someone.',
    parameters: {
      'type': 'object',
      'properties': {
        'phone': {'type': 'string', 'description': 'Phone number'},
        'message': {'type': 'string', 'description': 'SMS content'},
      },
      'required': ['phone', 'message'],
    },
  );

  static final Tool openSettings = Tool(
    name: 'open_settings',
    description: 'Open the device Settings application. '
        'Use this ONLY when the user explicitly asks to open '
        'or go to device settings.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );

  static final Tool takeScreenshot = Tool(
    name: 'take_screenshot',
    description: 'Capture a screenshot of the current screen. '
        'Use this ONLY when the user explicitly asks to take '
        'a screenshot or capture the screen.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );
}

import 'package:flutter_gemma/flutter_gemma.dart';

class NovaTools {
  static final List<Tool> all = [
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
    description: 'Get the current time, date, and day of the week',
    parameters: {'type': 'object', 'properties': {}},
  );

  static final Tool setAlarm = Tool(
    name: 'set_alarm',
    description: 'Set a device alarm',
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
    description: 'Cancel an existing alarm',
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
    description: 'Open an application by its package name',
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
    description: 'Open the browser with a web search',
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
    description: 'Get the current weather for a location',
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
    description: 'Send an SMS message',
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
    description: 'Open the device Settings app',
    parameters: {'type': 'object', 'properties': {}},
  );

  static final Tool takeScreenshot = Tool(
    name: 'take_screenshot',
    description:
        'Capture the current screen and return its size. '
        'Use this before asking about what is on screen.',
    parameters: {'type': 'object', 'properties': {}},
  );
}

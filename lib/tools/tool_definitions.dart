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
    createTask,
    listTasks,
    completeTask,
    createNote,
    searchNotes,
    listNotes,
  ];

  static final Tool getTime = Tool(
    name: 'get_time',
    description:
        'Get the current time, date, and day of the week. '
        'Use this ONLY when the user explicitly asks for the '
        'current time, date, or what day it is.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );

  static final Tool setAlarm = Tool(
    name: 'set_alarm',
    description:
        'Set a device alarm. Call immediately when the user gives a time — '
        'do not ask again for information already in the message. '
        'Convert 12-hour times to 24-hour: 7 AM → hour=7, 7 PM → hour=19, '
        'noon → 12, midnight → 0. If minutes are omitted, use minute=0. '
        'Example: "set alarm for 7pm" → set_alarm(hour=19, minute=0).',
    parameters: {
      'type': 'object',
      'properties': {
        'hour': {
          'type': 'integer',
          'description': 'Hour in 24-hour format (0-23). 7 AM=7, 7 PM=19.',
        },
        'minute': {
          'type': 'integer',
          'description': 'Minute (0-59). Default to 0 if the user did not specify minutes.',
        },
        'message': {'type': 'string', 'description': 'Alarm label/message'},
      },
      'required': ['hour', 'minute'],
    },
  );

  static final Tool cancelAlarm = Tool(
    name: 'cancel_alarm',
    description:
        'Cancel an existing alarm on the device. '
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
    description:
        'Open an application on the device. '
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
    description:
        'Open a web browser and perform a search. '
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
    description:
        'Get current weather information for a specific location. '
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
    description:
        'Send an SMS text message to a phone number. '
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
    description:
        'Open the device Settings application. '
        'Use this ONLY when the user explicitly asks to open '
        'or go to device settings.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );

  static final Tool takeScreenshot = Tool(
    name: 'take_screenshot',
    description:
        'Capture a single screenshot of the current screen. '
        'Use this ONLY when the user explicitly asks to take '
        'a screenshot or capture what is on screen. '
        'This captures ONE static image, not a video or stream.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );

  static final Tool createTask = Tool(
    name: 'create_task',
    description:
        'Create a new to-do task. '
        'Use this ONLY when the user asks to create, add, or remember a task or to-do item.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{
        'title': {'type': 'string', 'description': 'Task title'},
        'description': {
          'type': 'string',
          'description': 'Task details or description',
        },
        'priority': {'type': 'string', 'description': 'Priority level'},
        'due_date': {
          'type': 'string',
          'description': 'Due date in ISO 8601 format (YYYY-MM-DD)',
        },
        'tags': {'type': 'string', 'description': 'Comma-separated tags'},
      },
      'required': ['title'],
    },
  );

  static final Tool listTasks = Tool(
    name: 'list_tasks',
    description:
        'List pending to-do tasks. '
        'Use this when the user asks about their tasks, to-dos, or what they need to do.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );

  static final Tool completeTask = Tool(
    name: 'complete_task',
    description:
        'Mark a to-do task as completed. '
        'Use this when the user wants to check off, finish, or complete a task.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{
        'title': {
          'type': 'string',
          'description': 'Title of the task to complete (fuzzy match ok)',
        },
      },
      'required': ['title'],
    },
  );

  static final Tool createNote = Tool(
    name: 'create_note',
    description:
        'Save a note. '
        'Use this when the user asks to save, remember, or note something down.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{
        'title': {'type': 'string', 'description': 'Note title'},
        'content': {'type': 'string', 'description': 'Note content'},
        'tags': {'type': 'string', 'description': 'Comma-separated tags'},
      },
      'required': ['title', 'content'],
    },
  );

  static final Tool searchNotes = Tool(
    name: 'search_notes',
    description:
        'Search through saved notes. '
        'Use this when the user asks to find, look up, or recall saved notes.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{
        'query': {'type': 'string', 'description': 'Search query'},
      },
      'required': ['query'],
    },
  );

  static final Tool listNotes = Tool(
    name: 'list_notes',
    description: 'List recent or pinned notes.',
    parameters: <String, Object>{
      'type': 'object',
      'properties': <String, Object>{},
    },
  );
}

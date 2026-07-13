# Task 4: Contextual Tool Filtering

## Goal

Reduce search_web over-triggering by:
1. Updating tool descriptions to be more specific about when each tool should be used
2. Not passing `NovaTools.all` unconditionally — only pass the most relevant tools per query

## Files to Modify

- `lib/tools/tool_definitions.dart` — update `searchWeb.description` and other tool descriptions
- `lib/screens/assistant_screen.dart` — filter tools per query instead of using `NovaTools.all`

## Changes Required

### 1. Update tool descriptions in `lib/tools/tool_definitions.dart`

**searchWeb** (line 79-89) — make description explicit about when NOT to use:
```dart
static final Tool searchWeb = Tool(
  name: 'search_web',
  description:
      'Open a web browser and perform a search. '
      'Use this ONLY when the user explicitly asks to search, '
      'look up, find online, or check the internet for something. '
      'Do NOT use this for general questions, greetings, or '
      'conversations that can be answered from local knowledge.',
  parameters: <String, Object>{
    'type': 'object',
    'properties': <String, Object>{
      'query': <String, Object>{
        'type': 'string',
        'description': 'The search query to look up on the web',
      },
    },
    'required': <String>['query'],
  },
);
```

**getTime** (line 14-24) — clarify it's for explicit time requests:
```dart
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
```

**setAlarm** (line 26-44) — clarify it's for setting device alarms:
```dart
static final Tool setAlarm = Tool(
  name: 'set_alarm',
  description:
      'Set an alarm on the device. '
      'Use this ONLY when the user explicitly asks to set, '
      'create, or schedule an alarm or timer.',
  parameters: <String, Object>{...},
);
```

**cancelAlarm** (line 46-62) — similar clarification:
```dart
static final Tool cancelAlarm = Tool(
  name: 'cancel_alarm',
  description:
      'Cancel an existing alarm on the device. '
      'Use this ONLY when the user explicitly asks to cancel '
      'or remove an existing alarm.',
  parameters: <String, Object>{...},
);
```

**openApp** (line 64-76) — clarify:
```dart
static final Tool openApp = Tool(
  name: 'open_app',
  description:
      'Open an application on the device. '
      'Use this ONLY when the user explicitly asks to open '
      'or launch a specific application.',
  parameters: <String, Object>{...},
);
```

**getWeather** (line 108-124) — clarify:
```dart
static final Tool getWeather = Tool(
  name: 'get_weather',
  description:
      'Get current weather information for a specific location. '
      'Use this ONLY when the user explicitly asks about weather, '
      'temperature, or conditions for a specific place.',
  parameters: <String, Object>{...},
);
```

**sendSms** (line 126-147) — clarify:
```dart
static final Tool sendSms = Tool(
  name: 'send_sms',
  description:
      'Send an SMS text message to a phone number. '
      'Use this ONLY when the user explicitly asks to send '
      'a text message or SMS to someone.',
  parameters: <String, Object>{...},
);
```

**openSettings** (line 149-159) — clarify:
```dart
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
```

**takeScreenshot** (line 161-171) — clarify:
```dart
static final Tool takeScreenshot = Tool(
  name: 'take_screenshot',
  description:
      'Capture a screenshot of the current screen. '
      'Use this ONLY when the user explicitly asks to take '
      'a screenshot or capture the screen.',
  parameters: <String, Object>{
    'type': 'object',
    'properties': <String, Object>{},
  },
);
```

### 2. Update tool list construction in `lib/screens/assistant_screen.dart`

Replace `NovaTools.all` (line 310) with a helper that returns contextually relevant tools:

```dart
  List<Tool> _toolsForQuery(String query) {
    final tools = <Tool>[];
    final q = query.toLowerCase();

    // Always available: time, alarm, settings, screenshot
    tools.addAll([
      NovaTools.getTime,
      NovaTools.setAlarm,
      NovaTools.cancelAlarm,
      NovaTools.openSettings,
      NovaTools.takeScreenshot,
      NovaTools.openApp,
    ]);

    // Weather only if explicitly asked
    if (q.contains('weather') || q.contains('temperature') || q.contains('forecast')) {
      tools.add(NovaTools.getWeather);
    }

    // SMS only if explicitly asked
    if (q.contains('send') && (q.contains('sms') || q.contains('text') || q.contains('message'))) {
      tools.add(NovaTools.sendSms);
    }

    // Web search only if explicitly asked
    if (q.contains('search') || q.contains('look up') || q.contains('find online') || q.contains('google')) {
      tools.add(NovaTools.searchWeb);
    }

    return tools;
  }
```

Then update line 310 from:
```dart
tools: NovaTools.all,
```
to:
```dart
tools: _toolsForQuery(query),
```

**Note:** The variable `query` should be available in scope at that point (it's the user's message text).

## Acceptance Criteria

1. `searchWeb.description` explicitly says "use ONLY when user explicitly asks to search"
2. All other tool descriptions explicitly say "use ONLY when user explicitly asks"
3. `NovaTools.all` is not passed unconditionally
4. `_toolsForQuery()` returns contextually filtered tools based on query keywords
5. Web search is only included when query contains search-related keywords

## Key Implementation Notes

- Tool descriptions are what the AI model sees and uses to decide which tool to call
- Making descriptions more specific reduces accidental tool invocations
- The `_toolsForQuery()` function is a simple keyword filter — not a perfect solution but significantly reduces over-triggering
- The base set of always-available tools (time, alarm, settings, screenshot, openApp) are low-impact and don't cause problems if invoked accidentally
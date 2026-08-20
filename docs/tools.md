---
layout: default
title: Tools and MCP
---

# Tools and MCP

## Built-in device tools

| Tool | Description |
|------|-------------|
| `get_time` | Current time / date |
| `set_alarm` / `cancel_alarm` | Device alarms |
| `open_app` | Launch by package name |
| `search_web` | Browser search |
| `get_weather` | Weather lookup |
| `send_sms` | SMS compose/send |
| `open_settings` | System settings |
| `take_screenshot` | Capture via MediaProjection |
| `generate_image` | On-device diffusion image generation (Android) |

Definitions: `lib/tools/tool_definitions.dart`  
Native: `android/.../ToolExecutor.kt`

Progress streams over `EventChannel('dev.nova.assistant/tools_progress')`.

## Dart-side tools

Tasks and notes are executed in Dart (`TaskService`, `NoteService`) without native code.

## MCP

Nova supports:

- **HTTP + SSE** (legacy MCP transport)
- **stdio** (local process; Node required on device/host)

**Not yet:** Streamable HTTP + OAuth (e.g. Have I Been Pwned returns HTTP 405 on legacy GET SSE).

Configure servers in **Settings → MCP**. On connect failure, the UI shows a clear error.

## Screenshot / vision

1. Grant MediaProjection when prompted
2. Tool or UI requests capture → `ScreenshotService.requestCapture()`
3. Bytes fetched via screenshot MethodChannel
4. Orchestrator attaches `Message.withImage` when the active engine supports vision

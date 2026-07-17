---
layout: default
title: Architecture
---

# Architecture

## Layers

```
UI (screens / widgets)
        │
   ModelOrchestrator  ←── MemoryService (RAG), MCP, Tasks, Notes
        │
   flutter_gemma / LiteRT-LM
        │
   Platform channels → Android (tools, screenshot, assistant key)
```

## Key Dart services

| Service | Role |
|---------|------|
| `ModelOrchestrator` | Model load/unload, chat stream, tool loop, idle release |
| `ModelManager` | Download, disk register, prefs sync |
| `MemoryService` | Local RAG / conversation memory |
| `ToolExecutorService` | MethodChannel + progress EventChannel |
| `ScreenshotService` | MediaProjection frames via dedicated channel |
| `McpService` / `McpClient` | External MCP (HTTP/SSE, stdio) |
| `ParallelSessionManager` | Multi-chat (capped on Android) |
| `PlatformAdaptationService` | Platform capability flags + RAM warnings |

## Inference pipeline

1. User sends message (optional image / attachments)
2. RAG context retrieved
3. Model selected (`ModelSelector`) or override from UI
4. Engine loaded with `supportImage` when the model has vision
5. Stream tokens via `generateChatResponseAsync`
6. Tool calls executed; results fed back (multi-round)
7. Idle timer / lifecycle may unload the model **only after** streaming ends

## Native Android

| Component | Purpose |
|-----------|---------|
| `MainActivity` | Flutter host, channels, MediaProjection result |
| `AssistantActivity` | System assistant entry + screenshot handoff |
| `ScreenCaptureHelper` | MediaProjection, on-demand JPEG frames |
| `MediaProjectionService` | FGS for API 34+ projection |
| `ToolExecutor` | Alarms, apps, SMS, weather, etc. |

## Stability rules (critical)

- **Never** `close()` the LiteRT engine while `_isStreaming` is true (SIGABRT)
- Vision models must load with `supportImage: true` even for text-only first turns
- Screenshot bytes travel via `ScreenshotService`, not large MethodChannel maps
- Prefer SmolLM / Gemma 3 1B on ≤6 GB RAM devices for long debug sessions

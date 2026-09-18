---
layout: default
title: Assistant mode
---

<link rel="stylesheet" href="{{ '/assets/css/nova-docs.css' | relative_url }}">

# Assistant mode & screen capture

Nova can act as the **system assistant** (long-press home / power / gesture)
and capture the screen via **MediaProjection** for vision context.

## Set Nova as default assistant

1. Open **Settings → Assistant → Default assistant**
2. Or open Android **Settings → Apps → Default apps → Digital assistant app**
   and choose **Nova**

On API 30+, Nova checks `ROLE_ASSISTANT` and opens Voice Input settings when
you tap the tile.

## Screen capture (MediaProjection)

Capture is **not** a static install-time permission. Android shows a system
consent dialog the first time Nova requests projection. Grant it when prompted.

Foreground service type: `mediaProjection` (see `MediaProjectionService` in
the Android module).

## AppOps: PROJECT_MEDIA (debug / power-user)

On Android 14+ and many OEM builds, assistant overlay capture may also need
the `PROJECT_MEDIA` AppOps grant. This is a **developer / power-user** step —
Play Store users still get the normal MediaProjection prompt.

```bash
adb shell appops set dev.nova.assistant PROJECT_MEDIA allow
```

Verify:

```bash
adb shell appops get dev.nova.assistant PROJECT_MEDIA
```

If the assistant overlay cannot draw over other apps:

```bash
adb shell appops set dev.nova.assistant SYSTEM_ALERT_WINDOW allow
```

Revoke later with `deny` instead of `allow` if needed.

## Related

- [Tools & MCP](tools.md) — `take_screenshot` tool flow
- [Architecture](architecture.md) — ScreenshotService / ScreenCaptureHelper
- [Getting started](getting-started.md) — build and run

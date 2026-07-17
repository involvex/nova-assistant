---
layout: default
title: Getting started
---

# Getting started

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter | `3.47.0-0.1.pre` (beta channel) |
| Dart | matches Flutter SDK (`pubspec.yaml`) |
| Android SDK | API 26+, NDK as in `android/app/build.gradle.kts` |
| Device | Prefer **arm64-v8a** physical device (≥6 GB RAM for Gemma 4 E2B) |

On Windows, use PowerShell or Git Bash. For wireless ADB, keep a **single** device connection (`adb devices`).

## Clone and install

```bash
git clone https://github.com/involvex/nova-assistant.git
cd nova-assistant
flutter pub get
```

## Run

```bash
# List devices
flutter devices

# Run debug on Android
flutter run -d android

# Hot reload: r   Hot restart: R
```

## Build

```bash
flutter build apk --debug --target-platform android-arm64
flutter build apk --release
flutter build appbundle --release
```

## Verify before committing

```bash
dart format --set-exit-if-changed .
flutter analyze --no-pub
flutter test
```

CI runs the same checks on every push to `main`.

## First-run models

On first launch, use onboarding or **Settings → AI Models** to download or import a model:

- **SmolLM / Gemma 3 1B** — lighter soak testing (good for mid-range phones)
- **Gemma 4 E2B** — vision + thinking; needs significant free RAM
- **Import** — `.litertlm` or `.task` from storage (GGUF is blocked)

Optional: set a HuggingFace token in Settings for authenticated downloads.

## Agent-assisted setup

Open the repo in Cursor (or another agent) and ask:

> use the nova_dev skill to setup and build the app

See [`.cursor/skills/nova-dev/SKILL.md`](https://github.com/involvex/nova-assistant/blob/main/.cursor/skills/nova-dev/SKILL.md).

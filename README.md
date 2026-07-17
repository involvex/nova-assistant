# Nova Assistant

> An on-device AI assistant powered by Gemma, built with Flutter.

Nova runs AI models entirely on your device — no chat data is sent to external servers. Voice input, screen awareness, tools, RAG memory, and MCP integrations are all local-first.

**Docs site:** [GitHub Pages](https://involvex.github.io/nova-assistant/) (after Pages is enabled) · source in [`docs/`](docs/)

**Agent skill:** [`.cursor/skills/nova-dev`](.cursor/skills/nova-dev/SKILL.md) — tell any coding agent: *use the nova_dev skill to setup and build the app*

## Features

- **On-device AI** — Gemma / LiteRT via `flutter_gemma`
- **Multi-model** — SmolLM, FastVLM, Gemma 3 1B, Gemma 4 E2B + custom import
- **Voice** — speech-to-text input
- **Screen awareness** — MediaProjection screenshots for vision models
- **Tools** — alarms, apps, web, weather, SMS, settings, screenshot
- **Tasks & notes** — local productivity tools exposed to the model
- **RAG memory** — conversation + custom memories
- **MCP** — HTTP/SSE and stdio external tools (Streamable HTTP TBD)
- **Beginner / Expert** UI modes and onboarding
- **Battery-aware** idle model unload (safe with active streams)

## Supported models

| Model | Size | Vision | Thinking | Tools | Format |
|-------|------|--------|----------|-------|--------|
| SmolLM-135M | 135MB | No | No | Yes | `.task` |
| FastVLM-0.5B | 500MB | Yes | No | Yes | `.litertlm` |
| Gemma 3 1B | 500MB | No | No | Yes | `.litertlm` |
| Gemma 4 E2B | 2400MB | Yes | Yes | Yes | `.litertlm` |

GGUF is not supported. Prefer SmolLM / Gemma 3 1B on phones with ≤6 GB RAM.

## Getting started

### Prerequisites

- Flutter **3.47.0-0.1.pre** (beta) — see `pubspec.yaml`
- Android device/emulator **API 26+** (arm64 recommended)
- Android Studio or VS Code / Cursor

### Install and run

```bash
git clone https://github.com/involvex/nova-assistant.git
cd nova-assistant
flutter pub get
flutter run -d android
```

### Build

```bash
flutter build apk --debug --target-platform android-arm64
flutter build apk --release
flutter build appbundle --release
```

### Agent-assisted setup

```text
use the nova_dev skill to setup and build the app
use nova_dev to configure my own model
```

## Project structure

```
nova-assistant/
  lib/                 # Dart app (models, screens, services, tools)
  android/             # Kotlin native (tools, capture, assistant)
  docs/                # Documentation site (GitHub Pages)
  test/                # Unit / widget tests
  .cursor/skills/      # Agent skills (nova-dev)
  AGENTS.md            # Full coding agent guide
  ROADMAP.md           # Product roadmap
```

There is **no** `android.backup/` — that stale tree was removed.

## Architecture (brief)

1. UI → `ModelOrchestrator.processMessage`
2. RAG + model select + `flutter_gemma` stream
3. Tool calls → Dart services or Android `ToolExecutor`
4. Idle / lifecycle unload **after** streaming completes

Details: [docs/architecture.md](docs/architecture.md) · [AGENTS.md](AGENTS.md)

## Development

```bash
flutter pub get
dart format .
flutter analyze --no-pub
flutter test
```

CI (`.github/workflows/ci.yml`) runs format, analyze, tests, and a debug APK build on `main`.

## Privacy

- 100% on-device inference
- No analytics by default
- Local storage only (SharedPreferences / SQLite / app files)

## Platform support

| Platform | Status |
|----------|--------|
| Android | Supported |
| Web | Limited (vision / thinking / tools constrained) |
| Windows | Experimental |

## Contributing

See [docs/contributing.md](docs/contributing.md) and [ROADMAP.md](ROADMAP.md).

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- [Flutter](https://flutter.dev/)
- [flutter_gemma](https://pub.dev/packages/flutter_gemma)
- [Gemma](https://ai.google.dev/gemma)
- [HuggingFace](https://huggingface.co/)

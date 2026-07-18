---
layout: default
title: Nova Assistant Docs
---

# Nova Assistant

**On-device AI assistant** powered by Gemma, built with Flutter.
All inference runs locally — no chat data is sent to external servers.

## Documentation

| Page | Description |
|------|-------------|
| [Getting started](getting-started.md) | Clone, setup, run, and build |
| [Architecture](architecture.md) | Services, inference pipeline, native bridges |
| [Models](models.md) | Built-in models, import, HuggingFace downloads |
| [Remote LAN inference](remote-inference.md) | Stream large/GGUF models from a PC on Wi‑Fi |
| [Tools & MCP](tools.md) | Device tools and external MCP servers |
| [Contributing](contributing.md) | Style, tests, CI, commits |
| [Roadmap](roadmap.md) | Planned features and release phases |
| [Feature plan](plan-features.md) | Living feature plan and next work |
| [AGENTS.md](agents.md) | Full agent coding guide |

## Agent skill

Developers and coding agents can use the project skill:

**`.cursor/skills/nova-dev/SKILL.md`** (`nova-dev`)

Say in any agent tool:

> use the nova_dev skill to setup and build the app

or

> use nova_dev to configure my own model

## Quick start

```bash
git clone https://github.com/involvex/nova-assistant.git
cd nova-assistant
flutter pub get
flutter run -d android
```

**Requirements:** Flutter `3.47.0-0.1.pre` (beta), Dart matching `pubspec.yaml`, Android API 26+, arm64 device recommended.

## Privacy

- Inference is 100% on-device
- No analytics by default
- Models from trusted HuggingFace sources

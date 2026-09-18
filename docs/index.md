---
layout: default
title: Nova Assistant Docs
---

<link rel="stylesheet" href="{{ '/assets/css/nova-docs.css' | relative_url }}">

# Nova Assistant

**On-device AI assistant** powered by Gemma, built with Flutter.
All inference runs locally — no chat data is sent to external servers.

## Documentation

| Page | Description |
|------|-------------|
| [Getting started](getting-started.md) | Clone, setup, run, and build |
| [Architecture](architecture.md) | Services, inference pipeline, native bridges |
| [Models](models.md) | Built-in models, diffusion, import, HuggingFace |
| [Remote LAN inference](remote-inference.md) | Stream large/GGUF models from a PC on Wi‑Fi |
| [Tools & MCP](tools.md) | Device tools and external MCP servers |
| [Assistant mode](assistant-mode.md) | Default assistant, MediaProjection, `PROJECT_MEDIA` |
| [Contributing](contributing.md) | Style, tests, CI, commits |
| [Roadmap](roadmap.md) | Planned features and release phases |
| [Feature plan](plan-features.md) | Living feature plan and next work |
| [AGENTS.md](agents.md) | Full agent coding guide |

## Support the project

- [GitHub Sponsors](https://github.com/sponsors/involvex)
- [Buy Me a Coffee](https://buymeacoffee.com/involvex)
- [PayPal](https://paypal.me/involvex)
- Source: [github.com/involvex/nova-assistant](https://github.com/involvex/nova-assistant)

## Agent skill

Developers and coding agents can use the project skill:

[`.cursor/skills/nova-dev/SKILL.md`](https://github.com/involvex/nova-assistant/blob/main/.cursor/skills/nova-dev/SKILL.md) (`nova-dev`)

Also mirrored for other agents under `.agents/skills/nova-dev/` and `.claude/skills/nova-dev/` (sync with `scripts/link-nova-dev-skill.ps1` / `.sh`).

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

**Requirements:** Flutter `>=3.17.0-0.1.pre` (see `pubspec.yaml`), Dart matching
the Flutter SDK, Android API 26+, arm64 device recommended.

## Privacy

- Inference is 100% on-device (unless you enable Remote LAN)
- No analytics by default
- Models from trusted HuggingFace sources

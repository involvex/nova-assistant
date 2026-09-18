---
name: nova-dev
description: >-
  Setup, build, run, and develop Nova Assistant (Flutter on-device Gemma app).
  Use when the user says nova_dev, nova-dev, setup Nova, build the app, configure
  my own model, import a model, run on Android, debug image generation / Remote
  LAN / themes, or asks how Nova development works.
---

# Nova Assistant development skill

You are helping a developer work on **Nova Assistant** — a Flutter app that runs Gemma / LiteRT models **entirely on-device**.

Repo root should contain `pubspec.yaml` with `name: nova_assistant` and `AGENTS.md`.

**Canonical path:** `.cursor/skills/nova-dev/`  
**Other agents:** `.agents/skills/nova-dev/` (synced copy) · `.claude/skills/nova-dev/` (junction → `.agents`)  
Edit the Cursor copy, then run `./scripts/link-nova-dev-skill.ps1` (or `.sh`) to sync. Use `-LiveLink` / `--live` to junction `.agents` → `.cursor` for single-edit local work.

## When invoked

Follow the matching workflow below. Prefer running commands yourself. Do not invent API keys; HF token is optional in Settings.

---

## Workflow A — Setup and build the app

Say this when the user asks to **setup and build** Nova.

### 1. Preconditions

- Flutter matching `pubspec.yaml` (`flutter: '>=3.17.0-0.1.pre'`, Dart SDK constraint).
- Android SDK, API 26+, prefer physical **arm64** device.
- One ADB device only (`adb devices`). If duplicates: `adb disconnect` then reconnect once.

### 2. Bootstrap

```bash
flutter pub get
dart format --set-exit-if-changed . || dart format .
flutter analyze --no-pub
```

### 3. Run / build

```bash
flutter devices
flutter run -d android
# or
flutter build apk --debug --target-platform android-arm64
```

### 4. First model

Do **not** force-download Gemma 4 on low-RAM phones during soak tests. Guide the user to:

1. Open the app → onboarding or **Settings → AI Models**
2. Download **SmolLM** or **Gemma 3 1B**, or **Import from storage**
3. For vision/thinking demos, use Gemma 4 E2B only with enough free RAM

### 5. Verify

```bash
flutter test
```

Report device serial, Flutter version, and whether a model is installed.

---

## Workflow B — Configure my own model

Say this when the user wants a **custom / local model**.

### Supported formats

| Format | Supported |
|--------|-----------|
| `.litertlm` | Yes (preferred) |
| `.task` | Yes (MediaPipe) |
| `.gguf` | **No** on-device — use Remote LAN instead |
| Diffusion `.tflite` graphs | Yes — Settings → Models → Image generation |

### Steps

1. Confirm file format and approximate size.
2. Warn if ≥2 GB on ≤6 GB RAM devices.
3. In-app path: **Settings → AI Models → Import from storage** (or onboarding import).
4. Code path for agents debugging installs:
   - Registration: `ModelManager.registerDiskModel` / disk sync
   - Canonical name must match catalog (e.g. `gemma-4-E2B-it.litertlm`)
   - Avoid leaving `nova_download_<timestamp>_…` as the prefs name
5. After import, set preferred model in the model selector (or Auto).
6. Cold-start the app if the engine was already loaded without vision and the new model needs vision.

### HuggingFace download

- Optional token in Settings for gated models.
- Use Model Browser or built-in install URLs from `ModelHuggingFaceURLs`.
- On 401/403, ask user to set HF token — do not scrape private URLs.

### Diffusion (image generation)

- Catalog: Z-Image-Turbo (`Z-Image-Turbo-LiteRT`), FLUX.2-klein (`FLUX.2-klein-4B-LiteRT`).
- Files land under Flutter documents: `app_flutter/diffusion_models/<folder>/*.tflite`.
- Native channel IDs must use **folder names**, not Dart enum names (`zImageTurbo`).
- Uninstall via trash icon on Settings model cards (`uninstallDiffusionModel` / `uninstallModel`).

---

## Workflow C — Day-to-day development

### Read first

- `AGENTS.md` — architecture, lint rules, tools, models
- `docs/` — human docs (GitHub Pages); assistant capture: `docs/assistant-mode.md`
- `lib/services/model_orchestrator.dart` — inference + tools + idle unload
- `android/app/src/main/kotlin/dev/nova/assistant/` — native tools / capture / diffusion

### Stability invariants (do not regress)

1. **Never** close / clear LiteRT while streaming (`isStreaming`) — causes SIGABRT (`Callback invoked after it has been deleted`).
2. Vision-capable models load with `supportImage: true` always (not only when an image is present).
3. Screenshot pixels via `ScreenshotService` / `dev.nova.assistant/screenshot`, not huge tool MethodChannel maps.
4. Idle unload only after stream ends; lifecycle pause skips unload while streaming.
5. Remote LAN (`InferenceBackend.remote`): do not call `_getOrCreateModel` / pre-warm; re-read prefs each `processMessage`.

### Common commands

```bash
flutter pub get
flutter run -d android
flutter test
flutter analyze --no-pub
dart format .
dart run build_runner build --delete-conflicting-outputs   # if codegen needed
```

### Assistant mode / screen capture

```bash
adb shell appops set dev.nova.assistant PROJECT_MEDIA allow
adb shell appops get dev.nova.assistant PROJECT_MEDIA
```

See `docs/assistant-mode.md`.

### Commit style

Conventional Commits (`feat:`, `fix:`, `docs:`, …). Commit only when the user asks. Push only when the user asks.

---

## Project map (short)

```
lib/
  main.dart
  models/          # NovaModel, ChatMessage, roles, identity, palettes
  theme/           # NovaPalette (Hacker, Monokai, Dracula, …)
  screens/         # Assistant, settings, onboarding, MCP, tasks, notes
  services/        # Orchestrator, ModelManager, Memory, MCP, RemoteInference, …
  platform/        # ToolExecutorService, ScreenshotService
  tools/           # Tool JSON schemas
  widgets/
android/           # Kotlin: tools, MediaProjection, diffusion pipeline
docs/              # GitHub Pages site
.cursor/skills/nova-dev/   # canonical skill (edit here)
.agents/skills/nova-dev/   # synced for Codex / Agents SDK
.claude/skills/nova-dev/   # junction → .agents (Claude Code)
scripts/link-nova-dev-skill.ps1  # sync / live-link helper
scripts/link-nova-dev-skill.sh
```

## Out of scope for this skill

- Implementing Streamable HTTP + OAuth MCP (HIBP) unless explicitly requested
- Committing secrets, HF tokens, or `local.properties`
- Force-pushing `main`

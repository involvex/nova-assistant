# Nova Assistant Roadmap

This document outlines planned features and improvements for Nova Assistant.
Human-readable docs also live in [`docs/`](docs/) (GitHub Pages).

---

## Current Status (v0.2.1)

- [x] Basic chat interface with streaming responses
- [x] Multiple AI model support (SmolLM, FastVLM, Gemma 3, Gemma 4)
- [x] Automatic model selection based on query complexity
- [x] Voice input via speech-to-text
- [x] Screen capture and image attachment (on-demand MediaProjection)
- [x] Tool execution (alarms, apps, web search, weather, SMS)
- [x] Tool visualization + streaming progress (EventChannel)
- [x] RAG memory + custom memories
- [x] Agent identity + assistant roles
- [x] Model download, HF token, custom import (`.litertlm` / `.task`)
- [x] Beginner/Expert modes + onboarding
- [x] Tasks, notes, document analysis helpers
- [x] MCP client (HTTP/SSE + stdio) + MCP settings UI
- [x] Parallel sessions (capped to 1 on Android for RAM safety)
- [x] CI + release workflows; docs GitHub Pages workflow
- [x] **Stability:** no idle unload during LiteRT streaming (SIGABRT fix)
- [x] **Stability:** vision engines always load with `supportImage`
- [x] **Stability:** screenshot bytes via dedicated channel; capture not continuous
- [x] Agent skill [`.cursor/skills/nova-dev`](.cursor/skills/nova-dev/SKILL.md)

---

## Phase 1: Stability and Polish

### High Priority

- [x] Fix model re-download (canonical filename consistency)
- [x] Fix tool call truncation / multi-call support
- [x] Error handling (`ModelException` + action chips)
- [x] Memory management (RAG scoring / truncation)
- [x] Battery optimization (idle release, lifecycle-aware)
- [x] Offline mode indicator with Install action
- [x] Inference lifecycle hardening (stream vs unload race)
- [x] Vision engine always-on for vision models
- [x] Low-RAM Android defaults (shorter idle, session cap, memory warning)

### Medium Priority

- [x] File/URL attachment, export, history search, timestamps, copy, reactions
- [x] Onboarding + beginner/expert + model browser + import + selector
- [x] Debug mode + HF token + external tool providers
- [ ] Strip leftover debug `AGENT_DBG` instrumentation after soak verification
- [ ] Optional crash reporting (opt-in only)

---

## Phase 2: Enhanced Intelligence

### High Priority

- [x] Context window management
- [x] Multi-turn tool calls + visualization + streaming progress
- [x] Model performance metrics
- [x] MCP-like tool schemas + auto-model selection
- [ ] **MCP Streamable HTTP + OAuth** (HIBP and similar hosts; today HTTP 405 on legacy SSE)

### Medium Priority

- [x] Semantic search (TF-IDF)
- [ ] Conversation summaries
- [ ] Proactive suggestions
- [ ] Multi-language support
- [x] Code syntax highlighting (Markdown)
- [x] Document extract/chunk (KB UI still pending)
- [ ] Prompt presets
- [ ] Conversation branching
- [ ] Response regeneration (reroll)
- [x] Parallel session management
- [x] Platform adaptation helpers

---

## Phase 3: Platform Expansion

### High Priority

- [ ] Windows support (native)
- [ ] Linux support (native)
- [ ] Watch companion
- [x] Widget support (home screen widget; polish ongoing)
- [ ] Notification actions

### Medium Priority

- [ ] Voice synthesis (TTS)
- [ ] Wake word detection
- [ ] Real-time translation

---

## Phase 4: Advanced Features

### High Priority

- [ ] Multi-modal input (audio/video/docs beyond current attachments)
- [ ] Plugin system
- [ ] Optional encrypted cloud sync
- [x] MCP client (SSE/stdio)
- [ ] MCP Streamable HTTP transport

### Medium Priority

- [ ] Collaboration
- [ ] Learning mode
- [ ] Custom tool creation UI

---

## Phase 5: Ecosystem

### High Priority

- [ ] Nova API
- [x] MCP server management UI
- [ ] Home automation
- [ ] Calendar integration

### Medium Priority

- [ ] Email integration
- [x] Task management
- [x] Note taking
- [x] Document analysis (core)

---

## Technical Debt

### Code Quality

- [ ] Unit test coverage → 80%+
- [ ] Broader widget + integration tests
- [ ] Performance profiling cadence
- [ ] Public API docs beyond `docs/` + `AGENTS.md`

### Architecture

- [ ] Evaluate Riverpod/Bloc
- [ ] Explicit DI
- [ ] GoRouter migration
- [ ] i18n

### Build and CI/CD

- [x] Release workflow (tag APK)
- [x] CI analyze/test/build
- [x] Docs GitHub Pages workflow
- [ ] Fully automated release notes
- [ ] Optional opt-in crash analytics

---

## Model Roadmap

### Current

| Model | Status | Notes |
|-------|--------|-------|
| SmolLM-135M | Stable | Fast / low RAM |
| FastVLM-0.5B | Stable | Vision |
| Gemma 3 1B | Stable | Balanced |
| Gemma 4 E2B | Stable | Vision + thinking; high RAM |

### Planned

| Model | Status | Notes |
|-------|--------|-------|
| Gemma 4 E4B | Planned | Larger context |
| Llama 3.2 | Planned | Alt architecture |
| Phi-3 | Planned | Compact |
| Mistral | Planned | Alt |

---

## Release schedule

### v0.2.1 (current)

- Stability: stream-safe idle unload, vision load, screenshot pipeline
- Android low-RAM guards
- Docs site + `nova-dev` agent skill
- Repo cleanup (`android.backup` removed)

### v0.3.0 (next)

- MCP Streamable HTTP + OAuth
- Conversation summaries / regenerate / branching
- Coverage and widget test expansion
- Knowledge-base UI on top of document chunker

### v0.4.0

- Desktop targets, TTS, wake word

### Later

- Plugins, optional sync, ecosystem integrations

---

## Contributing

See [README](README.md), [docs/contributing.md](docs/contributing.md), and [AGENTS.md](AGENTS.md).
Use Conventional Commits. Ask coding agents to load **nova-dev** for setup/build/model import.

# Nova Assistant Roadmap

This document outlines planned features and improvements for Nova Assistant.
Human-readable docs also live in [`docs/`](docs/) (GitHub Pages).

---

## Current Status (v0.3.0)

- [x] Basic chat interface with streaming responses
- [x] Multiple AI model support (SmolLM, FastVLM, Gemma 3, Gemma 4)
- [x] Automatic model selection based on query complexity
- [x] Voice input via speech-to-text
- [x] **TTS speak response** on assistant bubbles
- [x] Screen capture and image attachment (on-demand MediaProjection)
- [x] Tool execution (alarms, apps, web search, weather, SMS)
- [x] Tool visualization + streaming progress (EventChannel)
- [x] RAG memory + custom memories
- [x] **Knowledge base UI** + real PDF text extraction → RAG
- [x] **Conversation summaries** (extractive, injected into RAG)
- [x] **Edit user message + resend**
- [x] Response regeneration (reroll)
- [x] Prompt presets
- [x] Agent identity + assistant roles
- [x] Model download, HF token, custom import (`.litertlm` / `.task`)
- [x] Beginner/Expert modes + onboarding
- [x] Tasks, notes, document analysis helpers
- [x] MCP client (HTTP/SSE + stdio + **Streamable HTTP** + OAuth/PKCE)
- [x] **Notification tap + quick actions** (open tasks / chat / ask Nova)
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
- [x] **MCP Streamable HTTP + OAuth**

### Medium Priority

- [x] Semantic search (TF-IDF)
- [x] Conversation summaries
- [ ] Proactive suggestions
- [ ] Multi-language support
- [x] Code syntax highlighting (Markdown)
- [x] Document extract/chunk + Knowledge base UI + PDF extract
- [x] Prompt presets
- [ ] Conversation branching
- [x] Response regeneration (reroll)
- [x] Parallel session management
- [x] Platform adaptation helpers

---

## Phase 3: Platform Expansion

### High Priority

- [ ] Windows support (native)
- [ ] Linux support (native)
- [ ] Watch companion
- [x] Widget support (home screen widget; polish ongoing)
- [x] Notification actions

### Medium Priority

- [x] Voice synthesis (TTS)
- [ ] Wake word detection
- [ ] Real-time translation

---

## Phase 4: Advanced Features

### High Priority

- [ ] Multi-modal input (audio/video/docs beyond current attachments)
- [ ] Plugin system
- [ ] Optional encrypted cloud sync
- [x] MCP client (SSE/stdio/Streamable HTTP)
- [x] MCP Streamable HTTP transport

### Medium Priority

- [ ] Collaboration
- [ ] Learning mode
- [ ] Custom tool creation UI

---

## Phase 5: Ecosystem

### High Priority

- [ ] Public plugin marketplace
- [ ] Third-party model adapters
- [ ] Community prompt/tool packs

### Non-goals (near term)

- GGUF inference
- Re-warming FGS `ModelService`
- Continuous screenshot encode

---

## Suggested v0.3.x / v0.4 follow-ons

| Feature | Notes |
|---------|-------|
| Conversation branching | Non-linear history model |
| Share message sheet | Export exists; bubble share does not |
| Continuous dictation | `record` package unused beyond STT |
| Free-RAM gate before Gemma 4 | Soft warning exists |
| Strip `AGENT_DBG` | Hygiene after soak |
| Desktop (Windows) scaffold | Large platform lift |
| Wake word | Battery/privacy cost |
| Custom tool creator UI | After MCP HTTP soak |

# Nova Assistant Roadmap

This document outlines planned features and improvements for Nova Assistant.
Human-readable docs also live in [`docs/`](docs/) (GitHub Pages).

---

## Current Status (v0.4.4)

- [x] Basic chat interface with streaming responses
- [x] Multiple AI model support (SmolLM, FastVLM, Gemma 3, Gemma 4)
- [x] Automatic model selection based on query complexity
- [x] Voice input via speech-to-text
- [x] **TTS speak response** on assistant bubbles
- [x] Screen capture and image attachment (on-demand MediaProjection)
- [x] Tool execution (alarms, apps, web search, weather, SMS, tasks, notes)
- [x] Tool visualization + streaming progress (EventChannel)
- [x] RAG memory + custom memories
- [x] **Memory overview** (stored vs derived, promote, ask-about-me)
- [x] **Message limits** (model-aware caps + pre-send guards)
- [x] **Follow-up suggestions** (bulb button chips + reroll)
- [x] **Settings JSON backup** (export/import, no models)
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

### v0.4.x additions

- [x] Remote inference (OpenAI-compatible LAN client + settings screen)
- [x] Share intent (Android share sheet → open chat with shared text)
- [x] Adult mode (confirmation dialog + system prompt injection)
- [x] Task management tools (create, list, complete to-dos via AI)
- [x] Note management tools (create, search, list notes via AI)
- [x] Shizuku/root power-user tools (force-stop, app info, battery settings)
- [x] Custom prompt presets (full CRUD)
- [x] Session history reinjection (reinject chat context on send)
- [x] High-context KV budget + auto-compact
- [x] Keep-warm policy (prevent idle unload when active)
- [x] Model release policy (battery/RAM-aware release logic)
- [x] Memory diagnostics service
- [x] Settings backup/restore
- [x] Inference backend selection (LiteRT / MediaPipe / Remote)
- [x] Model capability badges on model cards
- [x] Theme toggle (dark/light/system) — suggestion P0 #1
- [x] Font scale setting — suggestion P0 #2
- [x] Pin important messages — suggestion P0 #3
- [x] Markdown export for conversations — suggestion P0 #4
- [x] Conversation fork (duplicate + edit from any point) — suggestion P0 #5

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
- [x] Remote inference (OpenAI-compatible LAN)

### Medium Priority

- [x] Semantic search (TF-IDF)
- [x] Conversation summaries
- [x] Proactive suggestions (bulb follow-up chips)
- [ ] Multi-language support
- [x] Code syntax highlighting (Markdown)
- [x] Document extract/chunk + Knowledge base UI + PDF extract
- [x] Prompt presets
- [x] Conversation branching (fork from any message) — suggestion P0 #5
- [x] Response regeneration (reroll)
- [x] Parallel session management
- [x] Platform adaptation helpers
- [ ] In-chat message search (filter within current thread)
- [ ] Battery-aware model switching (auto-downgrade on low battery)

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
- [x] Share intent (Android share sheet)

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
- [x] Learning mode (student assistant role exists; spaced-repetition drill TBD)
- [ ] Custom tool creation UI
- [ ] Structured data rendering (interactive tables + checklists in chat)
- [ ] Model benchmarking / comparison tool
- [ ] Context window usage visualization

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

## Suggested v0.4.x / v0.5 follow-ons

| Feature | Status | Notes |
|---------|--------|-------|
| Conversation branching | ✅ Done | `forkConversation` in ChatHistoryService |
| Share message sheet | ✅ Done | Android share intent integration |
| In-chat message search | Open | Filter within current thread (not inter-conversation) |
| Battery-aware model switching | Open | Auto-downgrade to lighter model on low battery |
| Chat wallpaper / bubble theme | Open | Personalization beyond light/dark mode |
| Context window visualization | Open | Progress bar showing tokens used vs limit |
| Model benchmarking tool | Open | Compare response quality/speed across models |
| Structured data rendering | Open | Interactive tables and checklists in chat |
| Smart quick actions | Open | Context-aware action chips (translate, task, email) |
| In-chat code execution | Open | Sandboxed run_code tool for code snippets |
| Calendar/event tools | Open | Create/list events via CalendarContract |
| Pull-to-refresh conversation list | Open | Standard UX pattern |
| Model storage breakdown | Open | Show MB per model in settings |
| Screen timeout during streaming | Open | Keep awake during generation |
| Continuous dictation | Open | `record` package unused beyond STT |
| Free-RAM gate before Gemma 4 | Open | Soft warning exists |
| Strip `AGENT_DBG` | Open | Hygiene after soak |
| Desktop (Windows) scaffold | Open | Large platform lift |
| Wake word | Open | Battery/privacy cost |
| Custom tool creator UI | Open | After MCP HTTP soak |
| Clipboard-aware analysis | Open | "Analyze clipboard" quick action |

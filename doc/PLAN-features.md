# Feature plan (living)

> Product phases: [ROADMAP.md](../ROADMAP.md) · Docs: [docs/](../docs/)
>
> **v0.3.0 slate shipped** (KB + PDF, MCP Streamable HTTP + OAuth, TTS,
> edit message, notification actions, conversation summaries).

---

## Shipped (do not re-implement)

| Area | Status | Notes |
|------|--------|-------|
| Streaming tool progress | Done | `ToolProgress` + EventChannel |
| Tasks / notes | Done | Services + screens + AI tools |
| Document extract/chunk | Done | + KB UI + Syncfusion PDF extract |
| Knowledge base → RAG | Done | `KnowledgeBaseService` + settings entry |
| MCP HTTP/SSE + stdio | Done | Legacy SSE still available |
| MCP Streamable HTTP + OAuth/PKCE | Done | Transport picker + token exchange UI |
| TTS speak response | Done | `flutter_tts` + Speak on bubbles |
| Edit user message + resend | Done | Truncate from turn and resend |
| Notification tap / actions | Done | Mirrors widget action IDs |
| Conversation summaries | Done | Extractive rolling summary → RAG |
| User memory overview | Done | Stored vs derived; promote; ask / inventory prompt |
| Assistant language | Done | Prefs `match`/`en`/`de`; system-prompt steering (UI stays English; full i18n later) |
| Message limits + stability guards | Done | Model-aware char caps; orchestrator pre-send validation |
| High context window + compact | Done | Gemma 4 KV 2048→4096 toggle; auto + manual compact of older turns |
| Adult mode | Done | Local prefs + system-prompt suffix; confirm dialog; still refuses illegal content |
| Settings JSON backup | Done | Export/import prefs, identity, MCP config, presets (no models) |
| Follow-up suggestions (bulb) | Done | 3 contextual chips + reroll above input |
| Response regeneration | Done | |
| Prompt presets | Done | |
| Parallel sessions | Done | Cap = 1 on Android |
| Screen capture | Done | On-demand JPEG; FGS on API 34+ |
| Inference stability | Done | No unload mid-stream; vision always-on |

---

## Next up (priority order)

Plans: [`docs/superpowers/plans/2026-07-18-README.md`](../docs/superpowers/plans/2026-07-18-README.md)

### P0 — Hygiene

1. **Soak-test cleanup** — Remove `AGENT_DBG` / ingest helpers after device verification (PR #6 / F1). Then bump **0.4.1**.

### P1 — UX / intelligence

2. **Conversation branching from a message** — [plan](../docs/superpowers/plans/2026-07-18-conversation-branching.md) (ready; implement after greenlight)  
3. Share message / chat sheet — [stub](../docs/superpowers/plans/2026-07-18-share-sheet-polish.md)  
4. Continuous dictation / audio attach — [stub](../docs/superpowers/plans/2026-07-18-dictation-audio.md)  
5. ~~Free-RAM hard gate before Gemma 4 load~~  
6. Heavy models / image gen — X8 Pro Max soak or [LAN remote](../docs/remote-inference.md); not F1 (see [models.md](../docs/models.md))  

### P2 — Platform

6. Windows / Linux desktop hardening  
7. Optional wake word  

### P3 — Quality

8. Raise unit/widget coverage toward 80%  
9. Integration tests for onboarding + model import  
10. Optional opt-in crash reporting  

---

## Explicit non-goals (for now)

- Re-adding `android.backup/` or any duplicate Android tree  
- Shipping GGUF inference  
- Starting stub `ModelService` FGS “to keep model warm” (increases RAM pressure)  
- Continuous frame encode for screen capture  

---

## How to extend features

1. Read [AGENTS.md](../AGENTS.md) and [docs/architecture.md](../docs/architecture.md)  
2. Load **nova-dev** skill for setup/build/model flows  
3. Prefer small PRs; run `dart format`, `flutter analyze`, `flutter test`  
4. Update this file + ROADMAP when a checkbox-level item ships  

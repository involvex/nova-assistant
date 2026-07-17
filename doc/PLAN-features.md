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
| Response regeneration | Done | |
| Prompt presets | Done | |
| Parallel sessions | Done | Cap = 1 on Android |
| Screen capture | Done | On-demand JPEG; FGS on API 34+ |
| Inference stability | Done | No unload mid-stream; vision always-on |

---

## Next up (priority order)

### P0 — Hygiene

1. **Soak-test cleanup** — Remove `AGENT_DBG` / ingest helpers after device verification.

### P1 — UX / intelligence

2. Conversation branching from a message  
3. Share message / chat sheet  
4. Continuous dictation / audio attach  
5. Free-RAM hard gate before Gemma 4 load  

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

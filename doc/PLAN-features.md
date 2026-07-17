# Feature plan (living)

> Replaces the completed July 2026 implementation brief for streaming tools /
> tasks / notes / documents. Those features shipped; this file tracks **what’s next**.
>
> Product phases: [ROADMAP.md](../ROADMAP.md) · Docs: [docs/](../docs/)

---

## Shipped (do not re-implement)

| Area | Status | Notes |
|------|--------|-------|
| Streaming tool progress | Done | `ToolProgress` + EventChannel |
| Tasks / notes | Done | Services + screens + AI tools |
| Document extract/chunk | Done | Core libs; KB UI still open |
| MCP HTTP/SSE + stdio | Done | HIBP-style Streamable HTTP **not** done |
| Parallel sessions | Done | Cap = 1 on Android |
| Screen capture | Done | On-demand JPEG; FGS on API 34+ |
| Inference stability | Done | No unload mid-stream; vision always-on |

---

## Next up (priority order)

### P0 — Product blockers

1. **MCP Streamable HTTP + OAuth**  
   - Problem: hosts like Have I Been Pwned return **HTTP 405** on legacy GET SSE.  
   - Work: new transport in `mcp_client.dart`, session headers, OAuth/PKCE UI.  
   - Estimate: multi-day.

2. **Soak-test cleanup**  
   - Remove `AGENT_DBG` / ingest helpers after device verification.  
   - Keep structured logging via `dart:developer` where useful.

### P1 — UX / intelligence

3. Conversation summaries for long chats  
4. Response regeneration (reroll)  
5. Conversation branching from a message  
6. Knowledge-base UI on `DocumentChunker`  
7. Prompt presets

### P2 — Platform

8. Windows / Linux desktop hardening  
9. TTS + optional wake word  
10. Notification quick-actions polish

### P3 — Quality

11. Raise unit/widget coverage toward 80%  
12. Integration tests for onboarding + model import  
13. Optional opt-in crash reporting

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

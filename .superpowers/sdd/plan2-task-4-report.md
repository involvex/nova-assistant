# Plan 2 Task 4 Report: Auto + Manual Context Compact in Chat

## Status

**DONE**

## Commit

| Hash | Message |
|------|---------|
| `6c6fd3a` | feat: auto and manual context compact in chat |

## What Was Implemented

### `lib/services/model_orchestrator.dart`

- Added `applyCompactedReplay(List<ChatMessage> retained)`:
  - Falls back to `setPendingReplayMessages` when no active chat
  - Builds replay via `SessionHistoryReinjection.buildReplayMessages` using `_tokenLimitFor` × budget ratio (`highContextBudgetRatio` or `contextBudgetRatio`)
  - Calls `clearHistory(replayHistory: replay)` with fallback to per-message `addQuery` on failure
- Updated `_validateQueryLength` → `validateTokenBudget` to pass `highContext: _highContextEnabled`

### `lib/screens/assistant_screen.dart`

- Imported `conversation.dart`
- Added `_historyTokenEstimate` getter (non-streaming, non-error message text)
- Updated `_messageHardLimit` / `_messageSoftLimit` to pass `highContext` + `historyTokenEstimate`
- Added `_maybeAutoCompact()` — runs before send when `autoCompactEnabled` and `maxChars < 800`
- Added `_manualCompact()` — user-triggered compact via AppBar
- Wired `await _maybeAutoCompact()` in `_sendMessage` after hard-limit check, before `setPendingReplayMessages`
- Updated `validateTokenBudget` error path with `highContext` + `historyTokenEstimate`
- Added `IconButton(Icons.compress)` with tooltip "Compact context" in AppBar (disabled while generating)

## Test Commands Run

```bash
dart format .
flutter analyze
flutter test
```

**Results:**

- Analyze: **No issues found**
- Tests: **175/175 passed**

## Self-Review Notes

1. Auto-compact runs in the screen (v1 approach per plan) — orchestrator only applies replay
2. UI keeps full visible history; compacted replay targets inference session only
3. Character counter now reflects history token overhead and high-context setting
4. Ready for Task 5: documentation updates

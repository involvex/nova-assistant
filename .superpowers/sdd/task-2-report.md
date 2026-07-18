# Task 2 Report: Orchestrator Reinjection + Keep-Warm Flag

## Status

**DONE**

## Commit

| Hash | Message |
|------|---------|
| `61a058b` | feat: keep-warm policy and chat history reinjection |

## What Was Implemented

### `lib/services/model_release_policy.dart` (new)

Pure policy helpers per plan:

- `shouldReleaseOnPause` — blocks release when streaming or `keepModelWarm` is true
- `shouldReleaseOnIdle` — requires battery optimization; blocks when streaming or loading

### `lib/services/model_orchestrator.dart` (modified)

- `_keepModelWarm` field (default `true`), `keepModelWarm` getter, `setKeepModelWarm(bool)`
- `_loadKeepModelWarm()` loads `settings_keep_model_warm` from SharedPreferences (default `true`) in `initializeDefaultModel()`
- `_pendingReplay` + `setPendingReplayMessages(List<ChatMessage>)`
- `releaseIdleResources({bool force = false})` — early return when `!force && _keepModelWarm`; idle timer still calls `_releaseIdleResources` directly
- After fresh `createChat` (`wasNull` captured before assignment), replays `_pendingReplay` via `SessionHistoryReinjection.buildReplayMessages` with budget `(_tokenLimitFor(model) * _contextBudgetRatio).round()`, then `clearHistory(replayHistory:)` with `addQuery` fallback
- Imports: `chat_message.dart`, `session_history_reinjection.dart`

### `test/services/model_orchestrator_keep_warm_test.dart` (new)

Three unit tests for `ModelReleasePolicy` per plan.

## Test Commands Run

```bash
flutter test test/services/model_orchestrator_keep_warm_test.dart test/services/session_history_reinjection_test.dart
flutter analyze lib/services/model_orchestrator.dart lib/services/model_release_policy.dart
dart format .
```

**Results:**

- Tests: **5/5 passed** (3 keep-warm policy + 2 reinjection)
- Analyze: **No issues found**
- Format: 0 files changed

## Self-Review Notes

1. Task 2 scope only — `assistant_screen.dart` lifecycle and settings toggle deferred to Tasks 3–4.
2. `releaseIdleResources()` without `force: true` is now a no-op when keep-warm is on (default); existing pause handler still calls without `force` until Task 3 wires `ModelReleasePolicy`.
3. Reinjection runs only when chat was null before `createChat` and pending replay is non-empty.
4. Ready for Task 3: lifecycle gating + `setPendingReplayMessages` before send.

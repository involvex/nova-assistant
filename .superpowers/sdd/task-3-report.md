# Task 3 Report: Assistant Screen Lifecycle + Persist After Stream

## Status

**DONE**

## Commit

| Hash | Message |
|------|---------|
| `6493f29` | fix: stop unloading model on every pause; reinject on send; persist replies after stream |

## What Was Implemented

### `lib/screens/assistant_screen.dart` (modified)

1. **Import** — added `model_release_policy.dart`.

2. **Lifecycle (`didChangeAppLifecycleState`)** — replaced unconditional pause unload with `ModelReleasePolicy.shouldReleaseOnPause(keepModelWarm, isStreaming)`; calls `releaseIdleResources(force: true)` only when policy allows. Resume still calls `_checkModelAvailability()`.

3. **Replay before send** — `_sendMessage()` calls `ModelOrchestrator.instance.setPendingReplayMessages(...)` with non-streaming messages before clearing input, so orchestrator can reinject history after a cold reload.

4. **Save after stream** — `_sendMessage()` `finally` block now `await _saveMessages()` after `setState`, persisting completed assistant replies.

5. **Filter persistable messages** — `_saveMessages()` excludes streaming placeholders and empty assistant messages before writing to `ChatHistoryService` / `ConversationSummaryService`.

## Test Commands Run

```bash
dart format lib/screens/assistant_screen.dart
flutter analyze lib/screens/assistant_screen.dart
flutter test
```

**Results:**

- Format: 0 files changed
- Analyze: **No issues found**
- Tests: **171/171 passed**

## Self-Review Notes

1. Depends on Task 2 (`ModelReleasePolicy`, `keepModelWarm`, `setPendingReplayMessages`, `releaseIdleResources({force})`).
2. Early `_saveMessages()` on user send still runs (user message only); final save captures completed assistant reply.
3. With default `keepModelWarm: true`, pause no longer unloads the model unless user disables keep-warm in settings (Task 4).

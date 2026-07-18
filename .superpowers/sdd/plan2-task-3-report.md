# Plan 2 Task 3 Report: Compact Service API

## Status

**DONE**

## Commit

| Hash | Message |
|------|---------|
| `56675be` | feat: compactNow extractive context summarization |

## What Was Implemented

### `lib/services/conversation_summary_service.dart`

- Raised `_maxSummaryChars` from 1200 → **2000**
- Added `CompactResult` class with `summary` and `retainedMessages`
- Added `compactNow(Conversation conversation, {int keepRecent = 6})`:
  - Builds extractive summary via `_buildExtractiveSummary`
  - Computes usable messages (non-streaming, non-error, non-empty)
  - Returns `retainedMessages` = synthetic `[Conversation summary]` assistant note + last `keepRecent` usable turns
  - **UI-preserving:** does not modify `conversation.messages`; only persists `conversation.summary` via `ChatHistoryService.updateConversation`
  - Updates `activeSummary` on successful persist
  - Best-effort try/catch around persistence so `CompactResult` is always returned

### `test/services/conversation_summary_service_test.dart`

- Plan test: 12-message conversation, `keepRecent: 4`
- Asserts non-empty summary, retained count < full history, last retained message matches last original message
- Uses `SharedPreferences.setMockInitialValues({})` in `setUp` (repo pattern from `note_service_test.dart`)

## Test Commands Run

```bash
flutter test test/services/conversation_summary_service_test.dart
flutter analyze lib/services/conversation_summary_service.dart
```

**Results:**

- Tests: **1/1 passed**
- Analyze: **No issues found**

## Self-Review Notes

1. UI-preserving variant per plan: full message history untouched; orchestrator will use `retainedMessages` for replay (Task 4)
2. `CompactResult` exported from same file for orchestrator/screen wiring
3. Ready for Task 4: `applyCompactedReplay` + auto/manual compact in `assistant_screen.dart`

# Task 1 Report: Session History Reinjection Helper

## Status

**DONE**

## Commits

| Hash | Message |
|------|---------|
| `c6c9f96` | feat: add session history reinjection helper |

## What Was Implemented

Pure helper `SessionHistoryReinjection` that converts persisted UI `ChatMessage` turns into `flutter_gemma` `Message` objects for inference replay:

- `buildReplayMessages(List<ChatMessage> uiMessages, {required int maxTokens})` — filters streaming/error/empty messages, selects newest turns within token budget, returns oldest→newest for replay
- `estimateTokens(Message)` and `estimateChatMessageTokens(ChatMessage)` — text ≈ `length/4`, images = 500 tokens
- `_toMessage` — uses `Message.withImage` when `imageData` present, otherwise `Message(text:, isUser:)`

## Files Created

- `lib/services/session_history_reinjection.dart`
- `test/services/session_history_reinjection_test.dart`

## Test Commands Run

### Step 2 — Failing test (before implementation)

```bash
flutter test test/services/session_history_reinjection_test.dart
```

**Result:** FAIL (expected)

- Compilation error: `lib/services/session_history_reinjection.dart` not found
- Undefined name `SessionHistoryReinjection`

### Step 4 — Passing test (after implementation)

```bash
flutter test test/services/session_history_reinjection_test.dart
```

**Result:** PASS

```
00:00 +0: SessionHistoryReinjection skips errors streaming and empty
00:00 +1: SessionHistoryReinjection keeps newest turns within token budget
00:00 +2: All tests passed!
```

### Format + analyze

```bash
dart format lib/services/session_history_reinjection.dart test/services/session_history_reinjection_test.dart
flutter analyze lib/services/session_history_reinjection.dart test/services/session_history_reinjection_test.dart
```

**Result:**

- `dart format` reformatted `session_history_reinjection.dart` (trailing comma on `.where()` closure per project style)
- `flutter analyze`: 1 warning — unused import `package:flutter_gemma/flutter_gemma.dart` in test file (present in plan's exact test code; left unchanged per spec)

## Self-Review Notes

1. Implementation matches plan Task 1 Step 3 exactly; TDD flow followed (fail → implement → pass).
2. Token budget logic always includes at least the newest message even if it exceeds budget (`selected.isNotEmpty` guard on break).
3. Image messages use fixed 500-token estimate; no dedicated image test in Task 1 scope (covered by implementation, not exercised by current tests).
4. Minor analyze warning on unused test import is acceptable — test file copied verbatim from plan.
5. Ready for Task 2 wiring into `ModelOrchestrator`.

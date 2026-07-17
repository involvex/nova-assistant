# Plan 2 Task 1 Report: High-Context KV Budget

## Status

**DONE**

## Commit

| Hash | Message |
|------|---------|
| `595725b` | feat: high-context KV budget for longer user messages |

## What Was Implemented

### `lib/utils/message_limits.dart`

- Added `highContextBudgetRatio = 0.7`, `exhaustedBudgetFloorChars = 400`
- Reduced overhead: `gemma4JinjaOverheadTokens` 500→350, `systemPromptOverheadTokens` 300→220
- `kvTokenLimitFor(model, {bool highContext = false})` — Gemma 4 + highContext → 4096; Android + !highContext → 2048
- Threaded `highContext` through `maxUserCharsForInference`, `softUserCharsForInference`, `validateTokenBudget`, `isOverSoftLimit`
- When `highContext && gemma4E2b`, tier cap uses `MessageLimitTier.large` (8000 hard limit)
- Replaced exhausted floor `return 200` with `exhaustedBudgetFloorChars` (400)

### `lib/services/model_orchestrator.dart`

- Added `bool _highContextEnabled = false` (Task 2 will load prefs)
- Replaced duplicate `_tokenLimitFor` switch with `MessageLimits.kvTokenLimitFor(model, highContext: _highContextEnabled)`
- `_contextBudgetRatio` left at 0.6 for reinjection (Task 2 scope)

### `lib/services/parallel_session_manager.dart`

- Replaced duplicate `_tokenLimitFor` switch with `MessageLimits.kvTokenLimitFor(model, highContext: false)`
- Added `message_limits.dart` import

### `test/utils/message_limits_test.dart`

- Added three new tests: highContext KV 4096, empty session ≥4000 chars, low context ≥1500 chars
- Updated `validateTokenBudget` test to 5000 chars (overhead trim raised empty-session cap to ~2632)
- Updated existing tests to pass `highContext: false` explicitly; floor assertion uses `exhaustedBudgetFloorChars`

## Test Commands Run

```bash
flutter test test/utils/message_limits_test.dart test/services/model_orchestrator_budget_test.dart
flutter analyze lib/utils/message_limits.dart lib/services/model_orchestrator.dart lib/services/parallel_session_manager.dart
dart format lib/utils/message_limits.dart lib/services/model_orchestrator.dart lib/services/parallel_session_manager.dart test/utils/message_limits_test.dart
```

**Results:**

- Tests: **17/17 passed** (13 message_limits + 4 budget)
- Analyze: 1 info — `prefer_final_fields` on `_highContextEnabled` (intentionally mutable for Task 2)
- Format: no changes needed after write

## Budget Math (empty session, Gemma 4 Android)

| Mode | KV | Ratio | Usable | Reserved | Remaining tokens | Chars | Tier cap | Result |
|------|-----|-------|--------|----------|------------------|-------|----------|--------|
| low (`highContext: false`) | 2048 | 0.6 | 1228 | 570 | 658 | 2632 | 4000 (medium) | **2632** |
| high (`highContext: true`) | 4096 | 0.7 | 2867 | 570 | 2297 | 9188 | 8000 (large) | **8000** |

High-context empty session exceeds the ≥4000 char requirement.

## Self-Review Notes

1. TDD flow followed: tests updated first, then implementation.
2. DRY: orchestrator and parallel session manager no longer duplicate KV switch logic.
3. `model_orchestrator_budget_test.dart` unchanged — existing tests still pass with new constants.
4. Ready for Task 2: settings toggle + `refreshSettings` loading `_highContextEnabled`.

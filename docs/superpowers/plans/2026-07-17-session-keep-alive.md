# Session Keep-Alive + History Reinjection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After the user leaves and returns to Nova (retab / app switch), the conversation stays coherent — either the model stays warm, or a cold reload reinjects persisted chat turns into the new `InferenceChat` so it does not feel like a brand-new session.

**Architecture:** Split “battery unload” from “pause unload”. Stop calling `releaseIdleResources()` on every `AppLifecycleState.paused`. Add an optional **Keep model warm** setting (default: on for mid/high RAM, or simply default on with clear LMK warning). Independently, when `_activeChat` is created empty after a release, **replay** recent `ChatMessage`s from the UI conversation into LiteRT via `addQuery` / `clearHistory(replayHistory:)` so the model sees prior turns even after unload.

**Tech Stack:** Flutter, `flutter_gemma` (`InferenceChat`, `Message`), `SharedPreferences`, existing `ChatHistoryService` / `ChatMessage`.

## Global Constraints

- Never unload while `ModelOrchestrator.isStreaming` (SIGABRT risk).
- Do not start a permanent FGS just to keep the model warm (explicit non-goal in `doc/PLAN-features.md`).
- UI history already persists; this plan restores **inference** history.
- Android RAM pressure remains real for Gemma 4 E2B — keep battery optimization as an opt-in unload path.
- Prefer reinjection even when keep-warm is off (covers process death / idle unload).

## File map

| File | Responsibility |
|------|----------------|
| `lib/services/model_orchestrator.dart` | Keep-warm flag; reinject API; wire into `createChat` path |
| `lib/screens/assistant_screen.dart` | Lifecycle: stop always-unload on pause; pass messages on send/resume |
| `lib/screens/settings_screen.dart` | Toggle `settings_keep_model_warm` |
| `lib/services/settings_backup_service.dart` | Export/import new key |
| `test/services/session_history_reinjection_test.dart` | Pure helper tests for message → `Message` conversion + budget trim |
| `lib/services/session_history_reinjection.dart` | Pure functions: convert + trim history for reinjection |

---

### Task 1: Pure reinjection helper (TDD)

**Files:**
- Create: `lib/services/session_history_reinjection.dart`
- Test: `test/services/session_history_reinjection_test.dart`

**Interfaces:**
- Consumes: `ChatMessage` from `lib/models/chat_message.dart`
- Produces:
  - `List<Message> buildReplayMessages(List<ChatMessage> uiMessages, {required int maxTokens})`
  - Skips streaming, error, and empty messages
  - Keeps newest turns that fit `maxTokens` (estimate `text.length / 4`, images 500)
  - Uses `Message(text: ..., isUser: ...)` and `Message.withImage` when `imageData` present

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/services/session_history_reinjection.dart';

void main() {
  group('SessionHistoryReinjection', () {
    test('skips errors streaming and empty', () {
      final input = [
        ChatMessage(
          id: '1',
          text: '',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '2',
          text: 'hi',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
          isStreaming: true,
        ),
        ChatMessage(
          id: '3',
          text: 'boom',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
          isError: true,
        ),
        ChatMessage(
          id: '4',
          text: 'Hello',
          isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '5',
          text: 'Hi there',
          isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 10_000,
      );

      expect(replay.length, 2);
      expect(replay[0].text, 'Hello');
      expect(replay[0].isUser, isTrue);
      expect(replay[1].text, 'Hi there');
      expect(replay[1].isUser, isFalse);
    });

    test('keeps newest turns within token budget', () {
      final input = [
        for (var i = 0; i < 20; i++)
          ChatMessage(
            id: '$i',
            text: 'x' * 400, // ~100 tokens each
            isUser: i.isEven,
            timestamp: DateTime(2026, 1, 1),
          ),
      ];

      final replay = SessionHistoryReinjection.buildReplayMessages(
        input,
        maxTokens: 350, // ~3.5 messages
      );

      expect(replay.length, lessThanOrEqualTo(4));
      expect(replay.last.text, input.last.text);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/session_history_reinjection_test.dart -v`

Expected: FAIL — library / class not found.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/chat_message.dart';

/// Converts persisted UI chat turns into LiteRT replay messages.
class SessionHistoryReinjection {
  const SessionHistoryReinjection._();

  static const imageTokenEstimate = 500;

  static int estimateTokens(Message message) {
    if (message.hasImage) return imageTokenEstimate;

    return (message.text.length / 4).round();
  }

  static int estimateChatMessageTokens(ChatMessage message) {
    if (message.imageData != null && message.imageData!.isNotEmpty) {
      return imageTokenEstimate;
    }

    return (message.text.length / 4).round();
  }

  /// Newest-first fit into [maxTokens], returned oldest→newest for replay.
  static List<Message> buildReplayMessages(
    List<ChatMessage> uiMessages, {
    required int maxTokens,
  }) {
    final usable = uiMessages
        .where(
          (m) =>
              !m.isStreaming &&
              !m.isError &&
              m.text.trim().isNotEmpty,
        )
        .toList();

    final selected = <ChatMessage>[];
    var tokens = 0;
    for (var i = usable.length - 1; i >= 0; i--) {
      final msg = usable[i];
      final cost = estimateChatMessageTokens(msg);
      if (selected.isNotEmpty && tokens + cost > maxTokens) break;
      selected.add(msg);
      tokens += cost;
    }

    return selected.reversed.map(_toMessage).toList();
  }

  static Message _toMessage(ChatMessage m) {
    final bytes = m.imageData;
    if (bytes != null && bytes.isNotEmpty) {
      return Message.withImage(
        text: m.text,
        imageBytes: bytes,
        isUser: m.isUser,
      );
    }

    return Message(text: m.text, isUser: m.isUser);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/session_history_reinjection_test.dart -v`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/session_history_reinjection.dart test/services/session_history_reinjection_test.dart
git commit -m "feat: add session history reinjection helper"
```

---

### Task 2: Orchestrator reinjection + keep-warm flag

**Files:**
- Modify: `lib/services/model_orchestrator.dart`
- Test: `test/services/model_orchestrator_test.dart` (extend or add focused unit tests for flag load if practical; reinjection wiring may need a thin public method)

**Interfaces:**
- Consumes: `SessionHistoryReinjection.buildReplayMessages`
- Produces:
  - `bool keepModelWarm` (backed by prefs `settings_keep_model_warm`, default `true`)
  - `void setKeepModelWarm(bool enabled)`
  - `Future<void> setPendingReplayMessages(List<ChatMessage> messages)`
  - On `_activeChat ??= await createChat(...)`, if pending replay non-empty: call `chat.clearHistory(replayHistory: replay)` or sequential `addQuery` for each message **except** do not include the current outbound user query (caller passes history before current send)
  - `_releaseIdleResources` / public `releaseIdleResources`: if `keepModelWarm` is true, **return immediately** (same as battery optimization off for release path). Idle timer still respects battery optimization.
  - Clarify semantics:
    - `settings_battery_optimization` — idle timer unload after 2 min Android
    - `settings_keep_model_warm` — do **not** unload on pause / explicit release from lifecycle
    - When keep-warm is false, reinjection still runs after cold createChat

- [ ] **Step 1: Write failing tests for keep-warm gate**

Add to a new file `test/services/model_orchestrator_keep_warm_test.dart` that tests a small extracted pure gate if needed, **or** document manual verification if singleton prefs make unit tests brittle.

Prefer extracting:

```dart
// lib/services/model_release_policy.dart
class ModelReleasePolicy {
  static bool shouldReleaseOnPause({
    required bool keepModelWarm,
    required bool isStreaming,
  }) {
    if (isStreaming) return false;
    if (keepModelWarm) return false;

    return true;
  }

  static bool shouldReleaseOnIdle({
    required bool batteryOptimizationEnabled,
    required bool isStreaming,
    required bool isLoadingModel,
  }) {
    if (!batteryOptimizationEnabled) return false;
    if (isStreaming || isLoadingModel) return false;

    return true;
  }
}
```

Test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/model_release_policy.dart';

void main() {
  test('keep warm blocks pause release', () {
    expect(
      ModelReleasePolicy.shouldReleaseOnPause(
        keepModelWarm: true,
        isStreaming: false,
      ),
      isFalse,
    );
  });

  test('streaming always blocks pause release', () {
    expect(
      ModelReleasePolicy.shouldReleaseOnPause(
        keepModelWarm: false,
        isStreaming: true,
      ),
      isFalse,
    );
  });

  test('idle release respects battery flag', () {
    expect(
      ModelReleasePolicy.shouldReleaseOnIdle(
        batteryOptimizationEnabled: false,
        isStreaming: false,
        isLoadingModel: false,
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `flutter test test/services/model_orchestrator_keep_warm_test.dart -v`

- [ ] **Step 3: Implement policy + wire orchestrator**

1. Add `lib/services/model_release_policy.dart` as above.
2. In `ModelOrchestrator`:
   - Load `_keepModelWarm` from prefs in existing settings load / `refreshSettings` (default `true`).
   - Field `List<ChatMessage> _pendingReplay = const [];`
   - Method:

```dart
void setPendingReplayMessages(List<ChatMessage> messages) {
  _pendingReplay = List<ChatMessage>.from(messages);
}
```

3. After successful `createChat` when chat was null:

```dart
final createdFresh = _activeChat == null;
_activeChat ??= await inferenceModel.createChat(...);
if (createdFresh && _pendingReplay.isNotEmpty) {
  final budget = (_tokenLimitFor(model) * _contextBudgetRatio).round();
  final replay = SessionHistoryReinjection.buildReplayMessages(
    _pendingReplay,
    maxTokens: budget,
  );
  _pendingReplay = const [];
  if (replay.isNotEmpty) {
    try {
      await _activeChat!.clearHistory(replayHistory: replay);
    } on Exception catch (e) {
      debugPrint('History reinjection failed: $e');
      for (final msg in replay) {
        await _activeChat!.addQuery(msg);
      }
    }
  }
}
```

Note: capture `createdFresh` **before** assignment (`final wasNull = _activeChat == null`).

4. Public `releaseIdleResources` used by lifecycle should check keep-warm:

```dart
Future<void> releaseIdleResources({bool force = false}) async {
  if (!force && _keepModelWarm) return;
  await _releaseIdleResources();
}
```

Idle timer continues to call `_releaseIdleResources` directly (battery path).

- [ ] **Step 4: Run tests**

Run:

```bash
flutter test test/services/model_orchestrator_keep_warm_test.dart test/services/session_history_reinjection_test.dart
flutter analyze lib/services/model_orchestrator.dart lib/services/model_release_policy.dart
```

Expected: PASS / no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/services/model_release_policy.dart lib/services/model_orchestrator.dart test/services/model_orchestrator_keep_warm_test.dart
git commit -m "feat: keep-warm policy and chat history reinjection"
```

---

### Task 3: Assistant screen lifecycle + pass replay on send

**Files:**
- Modify: `lib/screens/assistant_screen.dart` (~468–477 and send path ~678+)

**Interfaces:**
- Consumes: `ModelReleasePolicy.shouldReleaseOnPause`, `ModelOrchestrator.setPendingReplayMessages`, `keepModelWarm`
- Produces: Lifecycle no longer always unloads; before `processMessage`, sets pending replay to `_messages` excluding the message about to be sent if already appended

- [ ] **Step 1: Change lifecycle handler**

Replace:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    if (!ModelOrchestrator.instance.isStreaming) {
      ModelOrchestrator.instance.releaseIdleResources();
    }
  } else if (state == AppLifecycleState.resumed) {
    _checkModelAvailability();
  }
}
```

With:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    final shouldRelease = ModelReleasePolicy.shouldReleaseOnPause(
      keepModelWarm: ModelOrchestrator.instance.keepModelWarm,
      isStreaming: ModelOrchestrator.instance.isStreaming,
    );
    if (shouldRelease) {
      ModelOrchestrator.instance.releaseIdleResources(force: true);
    }
  } else if (state == AppLifecycleState.resumed) {
    _checkModelAvailability();
  }
}
```

Expose `bool get keepModelWarm` on orchestrator.

- [ ] **Step 2: Before calling processMessage**

After user message is in `_messages` (or with prior list):

```dart
ModelOrchestrator.instance.setPendingReplayMessages(
  List<ChatMessage>.from(_messages.where((m) => !m.isStreaming)),
);
```

If the current user turn is already in `_messages`, reinjection helper must not duplicate it: either pass messages **before** appending the new user turn, or strip the last user message matching the outgoing query in the orchestrator when reinjecting.

Preferred: call `setPendingReplayMessages` with history **before** appending the outbound user `ChatMessage`.

- [ ] **Step 3: Manual device check checklist (document in commit body)**

1. Load Gemma 4, send “My name is Ada”.
2. Switch to another app 10s, return.
3. Ask “What is my name?” — must answer Ada without “new chat” amnesia.
4. Disable Keep model warm; enable battery optimization; background 3+ minutes until idle release; return; ask again — reinjection should still answer Ada (may reload model first).

- [ ] **Step 4: Commit**

```bash
git add lib/screens/assistant_screen.dart lib/services/model_orchestrator.dart
git commit -m "fix: stop unloading model on every pause; reinject on send"
```

---

### Task 4: Settings toggle + backup

**Files:**
- Modify: `lib/screens/settings_screen.dart` (Functionality section near battery toggle ~429)
- Modify: `lib/services/settings_backup_service.dart`

**Interfaces:**
- Prefs key: `settings_keep_model_warm` (bool, default `true`)
- On change: `ModelOrchestrator.instance.setKeepModelWarm(v)` + `_saveSetting`

- [ ] **Step 1: Add state + load**

```dart
bool _keepModelWarm = true;
// in _loadSettings:
_keepModelWarm = prefs.getBool('settings_keep_model_warm') ?? true;
```

- [ ] **Step 2: Add toggle tile** (near Battery optimization)

```dart
_toggleTile(
  icon: Icons.memory,
  title: 'Keep model warm',
  subtitle:
      'Stay loaded when you switch apps. Uses more RAM; turn off on low-memory phones.',
  value: _keepModelWarm,
  onChanged: (v) async {
    setState(() => _keepModelWarm = v);
    await _saveSetting('settings_keep_model_warm', v);
    ModelOrchestrator.instance.setKeepModelWarm(v);
  },
),
```

- [ ] **Step 3: Backup service**

Add `keepModelWarm` next to `batteryOptimization` in export/import maps using key `settings_keep_model_warm`.

- [ ] **Step 4: Analyze + test**

```bash
dart format lib/screens/settings_screen.dart lib/services/settings_backup_service.dart
flutter analyze lib/screens/settings_screen.dart lib/services/settings_backup_service.dart
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart lib/services/settings_backup_service.dart
git commit -m "feat: settings toggle for keep model warm"
```

---

### Task 5: Docs touch-up

**Files:**
- Modify: `doc/PLAN-features.md` — move “session keep-warm / reinjection” into shipped or next-up as Done when merged
- Modify: `docs/architecture.md` only if it documents lifecycle unload (optional one paragraph)

- [ ] **Step 1: Update PLAN-features shipped table**

Add row: `Session keep-warm + history reinjection | Done | Prefs keep_model_warm; replay ChatMessage into InferenceChat`

- [ ] **Step 2: Commit**

```bash
git add doc/PLAN-features.md
git commit -m "docs: mark session keep-warm as shipped"
```

---

## Self-review

1. Spec coverage: retab context loss → Tasks 2–3; visible history already OK; LMK risk → keep-warm toggle + existing battery idle.
2. No placeholders left in steps.
3. Types: `setPendingReplayMessages(List<ChatMessage>)`, `keepModelWarm`, `releaseIdleResources({bool force})` consistent across tasks.

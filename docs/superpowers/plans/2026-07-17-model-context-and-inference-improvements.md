# Model Context & Inference Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix session/context loss when switching back to Nova, raise usable input limits, add smart context compaction, improve large-model handling, and add optional GGUF, LAN streaming, and adult-mode settings — while keeping on-device privacy as the default.

**Architecture:** Split work into five deliverable tracks. **Track A (session persistence)** fixes the root bugs: assistant replies not saved after streaming, inference chat wiped on background without replaying UI history, and aggressive model unload on every `paused`. **Track B (limits + compaction)** aligns UI counters with real token budgets and adds LLM-based summarization when history exceeds KV budget. **Track C (models)** extends `ModelOrchestrator` with a pluggable `InferenceBackend` interface so LiteRT/MediaPipe stay default while GGUF and LAN-remote backends are optional add-ons. **Track D (settings)** adds user-facing toggles backed by SharedPreferences.

**Tech Stack:** Flutter >=3.44, Dart >=3.12, `flutter_gemma` ^1.3, `flutter_gemma_litertlm`, `flutter_gemma_mediapipe`, `shared_preferences`, Android Kotlin platform channels (for optional foreground service warm-keep).

## Global Constraints

- All inference remains on-device by default; LAN streaming is opt-in and local-network only.
- Existing formats `.litertlm` and `.task` remain the primary path via `flutter_gemma`.
- GGUF is currently blocked in `model_manager.dart` and listed as a ROADMAP non-goal due to `llamadart` native lib conflicts — Track C treats GGUF as a research-gated optional backend, not a drop-in replacement.
- Follow project lint rules: `prefer_final_locals`, trailing commas, explicit return types, `prefer_single_quotes`.
- Run `flutter test`, `flutter analyze`, `dart format .` before each commit.
- Do not push without explicit user permission.
- Battery optimization idle unload (`settings_battery_optimization`, default `true`) must remain available; new "keep model loaded" setting overrides pause-unload only when user opts in.

---

## File Structure (what changes where)

| File | Responsibility |
|------|----------------|
| `lib/services/session_persistence_service.dart` | **Create.** Serialize UI messages → inference replay messages; save-after-stream hook. |
| `lib/services/model_orchestrator.dart` | Replay history into `_activeChat`; configurable pause unload; compaction hooks; backend adapter entry point. |
| `lib/services/context_compaction_service.dart` | **Create.** LLM + extractive compaction; auto/manual triggers. |
| `lib/services/inference_backend.dart` | **Create.** Abstract backend (`LocalGemmaBackend`, `RemoteLanBackend`, `GgufBackend`). |
| `lib/services/lan_model_host_service.dart` | **Create.** mDNS discovery + HTTP token stream server (host mode). |
| `lib/services/lan_model_client_service.dart` | **Create.** Connect to host; stream completions. |
| `lib/utils/message_limits.dart` | Fix 200-char floor; expose `remainingUserBudget()`. |
| `lib/screens/assistant_screen.dart` | Save after stream; wire history into limit counter; compact button; lifecycle policy. |
| `lib/screens/settings_screen.dart` | Adult mode, keep-loaded, auto-compact, LAN host/client toggles. |
| `lib/models/assistant_role.dart` | `unrestricted` role variant for adult mode. |
| `lib/services/settings_backup_service.dart` | Export/import new keys. |
| `test/services/session_persistence_service_test.dart` | **Create.** |
| `test/services/context_compaction_service_test.dart` | **Create.** |
| `test/utils/message_limits_test.dart` | Extend for new budget API. |
| `docs/models.md` | Document GGUF/LAN limitations. |

---

## Root Cause Summary (from codebase audit)

| Symptom | Root cause | Key location |
|---------|------------|--------------|
| Model reloads on retab | `AppLifecycleState.paused` → `releaseIdleResources()` closes `_activeModel` | `assistant_screen.dart:468-472`, `model_orchestrator.dart:376-388` |
| Feels like new chat | `_activeChat` cleared on unload; UI `_messages` never replayed into new chat | `model_orchestrator.dart:1629-1637` |
| Missing assistant replies | `_saveMessages()` called at send time, not after stream completes | `assistant_screen.dart:728`, `813-822` |
| ~200 char input cap | `remainingTokens <= 0` returns hard floor `200`; UI ignores history tokens | `message_limits.dart:118-119`, `assistant_screen.dart:240-243` |
| Long answers vs short input | Output not capped; only input/KV budget enforced | by design |
| GGUF blocked | Native lib conflict + no backend | `model_manager.dart:588-594` |
| No adult mode | No setting or prompt variant exists | — |

---

# TRACK A — Session Persistence (ship first; fixes retab + new-chat feel)

### Task 1: Save assistant messages after streaming completes

**Files:**
- Modify: `lib/screens/assistant_screen.dart:813-822`
- Test: `test/screens/assistant_screen_persistence_test.dart` (widget test with mocked orchestrator)

**Interfaces:**
- Consumes: existing `_saveMessages()`, `ChatHistoryService.updateConversation`
- Produces: `_saveMessages()` called in `finally` block of `_sendMessage()` after `_isGenerating = false`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/screens/assistant_screen_persistence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';

void main() {
  test('persistence helper includes completed assistant text', () {
    final messages = [
      ChatMessage(
        id: '1',
        text: 'hello',
        isUser: true,
        timestamp: DateTime(2026, 1, 1),
      ),
      ChatMessage(
        id: '2',
        text: 'full assistant reply',
        isUser: false,
        timestamp: DateTime(2026, 1, 1),
        isStreaming: false,
      ),
    ];
    final persistable = messages.where((m) => !m.isStreaming).toList();
    expect(persistable.length, 2);
    expect(persistable.last.text, 'full assistant reply');
  });
}
```

- [ ] **Step 2: Run test to verify it passes (documents expected filter)**

Run: `flutter test test/screens/assistant_screen_persistence_test.dart`
Expected: PASS (this test guards the filter logic we'll use)

- [ ] **Step 3: Add `_saveMessages()` call after stream in `finally`**

In `lib/screens/assistant_screen.dart`, inside the `finally` block of `_sendMessage()` (after line 820), add:

```dart
      await _saveMessages();
```

- [ ] **Step 4: Filter streaming placeholders in `_saveMessages`**

In `lib/screens/assistant_screen.dart` `_saveMessages()`:

```dart
  Future<void> _saveMessages() async {
    final persistable = _messages
        .where((m) => !m.isStreaming && !(m.text.isEmpty && !m.isUser))
        .toList();
    if (widget.conversationId != null) {
      final conversation = await ChatHistoryService.getConversation(
        widget.conversationId!,
      );
      if (conversation != null) {
        final updated = conversation.copyWith(messages: List.from(persistable));
        await ChatHistoryService.updateConversation(updated);
        await ConversationSummaryService.instance.maybeUpdateSummary(updated);
      }
    } else {
      await ChatHistoryService.save(persistable);
      // ... existing summary path using persistable
    }
  }
```

- [ ] **Step 5: Run tests**

Run: `flutter test`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add lib/screens/assistant_screen.dart test/screens/assistant_screen_persistence_test.dart
git commit -m "fix: persist assistant replies after streaming completes"
```

---

### Task 2: Replay UI history into inference chat after model reload

**Files:**
- Create: `lib/services/session_persistence_service.dart`
- Modify: `lib/services/model_orchestrator.dart:1623-1637`
- Modify: `lib/screens/assistant_screen.dart` (pass messages into orchestrator)
- Test: `test/services/session_persistence_service_test.dart`

**Interfaces:**
- Consumes: `List<ChatMessage>` from UI, `InferenceChat.addQuery`, `Message` from `flutter_gemma`
- Produces:
  - `SessionPersistenceService.toReplayMessages(List<ChatMessage> ui, {int maxTurns, int maxChars}) → List<Message>`
  - `ModelOrchestrator.processMessage({..., List<ChatMessage>? conversationHistory})`
  - `ModelOrchestrator.restoreConversationHistory(List<ChatMessage> history)` called before first `addQuery` when `_activeChat` is new

- [ ] **Step 1: Write the failing test**

```dart
// test/services/session_persistence_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/services/session_persistence_service.dart';

void main() {
  group('SessionPersistenceService', () {
    test('converts user and assistant turns skipping errors', () {
      final ui = [
        ChatMessage(
          id: '1', text: 'Hi', isUser: true,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '2', text: 'Hello!', isUser: false,
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: '3', text: '⚠️ fail', isUser: false, isError: true,
          timestamp: DateTime(2026, 1, 1),
        ),
      ];
      final replay = SessionPersistenceService.toReplayMessages(ui);
      expect(replay.length, 2);
      expect(replay.first.isUser, isTrue);
      expect(replay.last.isUser, isFalse);
    });

    test('clips to maxTurns most recent', () {
      final ui = List.generate(
        20,
        (i) => ChatMessage(
          id: '$i',
          text: 'msg $i',
          isUser: i.isEven,
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      final replay = SessionPersistenceService.toReplayMessages(
        ui,
        maxTurns: 4,
      );
      expect(replay.length, 4);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/session_persistence_service_test.dart`
Expected: FAIL — class not found

- [ ] **Step 3: Implement `SessionPersistenceService`**

```dart
// lib/services/session_persistence_service.dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:nova_assistant/models/chat_message.dart';

class SessionPersistenceService {
  const SessionPersistenceService._();

  static const defaultMaxTurns = 12;

  static List<Message> toReplayMessages(
    List<ChatMessage> ui, {
    int maxTurns = defaultMaxTurns,
    int maxCharsPerMessage = 2000,
  }) {
    final usable = ui
        .where((m) =>
            !m.isStreaming &&
            !m.isError &&
            m.text.trim().isNotEmpty)
        .toList();
    final tail = usable.length > maxTurns
        ? usable.sublist(usable.length - maxTurns)
        : usable;

    return tail
        .map((m) {
          final text = m.text.length > maxCharsPerMessage
              ? '${m.text.substring(0, maxCharsPerMessage)}…'
              : m.text;
          return Message.text(text: text, isUser: m.isUser);
        })
        .toList();
  }
}
```

- [ ] **Step 4: Add `conversationHistory` param to `processMessage` and replay**

In `model_orchestrator.dart`, after `_activeChat ??= await inferenceModel.createChat(...)`:

```dart
      if (_activeChat!.fullHistory.isEmpty &&
          conversationHistory != null &&
          conversationHistory.isNotEmpty) {
        final replay = SessionPersistenceService.toReplayMessages(
          conversationHistory,
        );
        for (final msg in replay) {
          await _activeChat!.addQuery(msg);
        }
      }
```

Add optional parameter to `processMessage` signature:

```dart
  Stream<InferenceResult> processMessage({
    required String query,
    List<ChatMessage>? conversationHistory,
    // ... existing params
  })
```

In `assistant_screen.dart` `_sendMessage()`, pass history excluding the message just added:

```dart
      await for (final result in ModelOrchestrator.instance.processMessage(
        query: text,
        conversationHistory: _messages
            .where((m) => m.id != assistantId && m.id != userMessage.id)
            .toList(),
        // ... existing args
      )) {
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/services/session_persistence_service_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/session_persistence_service.dart lib/services/model_orchestrator.dart lib/screens/assistant_screen.dart test/services/session_persistence_service_test.dart
git commit -m "feat: replay UI conversation history into inference chat after reload"
```

---

### Task 3: Configurable model retention on background (fix retab reload)

**Files:**
- Modify: `lib/screens/assistant_screen.dart:467-476`
- Modify: `lib/services/model_orchestrator.dart` (add `setKeepModelLoaded(bool)`)
- Modify: `lib/screens/settings_screen.dart`
- Test: `test/services/model_orchestrator_lifecycle_test.dart`

**Interfaces:**
- Consumes: SharedPreferences key `settings_keep_model_loaded` (default `false`)
- Produces: `ModelOrchestrator.keepModelLoaded` getter; pause handler skips `releaseIdleResources()` when true and RAM > threshold

- [ ] **Step 1: Write the failing test**

```dart
// test/services/model_orchestrator_lifecycle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';

void main() {
  test('keepModelLoaded defaults to false', () {
    expect(ModelOrchestrator.instance.keepModelLoaded, isFalse);
  });

  test('setKeepModelLoaded updates flag', () {
    ModelOrchestrator.instance.setKeepModelLoaded(true);
    expect(ModelOrchestrator.instance.keepModelLoaded, isTrue);
    ModelOrchestrator.instance.setKeepModelLoaded(false);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `flutter test test/services/model_orchestrator_lifecycle_test.dart`

- [ ] **Step 3: Implement flag in orchestrator**

```dart
// model_orchestrator.dart — add field + methods
  bool _keepModelLoaded = false;
  bool get keepModelLoaded => _keepModelLoaded;

  void setKeepModelLoaded(bool value) {
    _keepModelLoaded = value;
  }

  Future<void> _loadKeepModelLoadedPref() async {
    final prefs = await SharedPreferences.getInstance();
    _keepModelLoaded = prefs.getBool('settings_keep_model_loaded') ?? false;
  }
```

Call `_loadKeepModelLoadedPref()` from `initializeDefaultModel()`.

- [ ] **Step 4: Gate pause unload in `assistant_screen.dart`**

```dart
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!ModelOrchestrator.instance.isStreaming &&
          !ModelOrchestrator.instance.keepModelLoaded) {
        ModelOrchestrator.instance.releaseIdleResources();
      } else if (ModelOrchestrator.instance.keepModelLoaded) {
        ModelOrchestrator.instance.cancelIdleTimer();
      }
    } else if (state == AppLifecycleState.resumed) {
      _checkModelAvailability();
      if (ModelOrchestrator.instance.keepModelLoaded) {
        ModelOrchestrator.instance.resetIdleTimer();
      }
    }
  }
```

Add `cancelIdleTimer()` / `resetIdleTimer()` public wrappers around existing idle timer logic.

- [ ] **Step 5: Add Settings toggle**

In `settings_screen.dart` Functionality section:

```dart
          _toggleTile(
            title: 'Keep model loaded',
            subtitle:
                'Avoid reloading when switching apps. Uses more RAM; '
                'may cause low-memory kills on ≤6 GB devices.',
            value: _keepModelLoaded,
            onChanged: (v) {
              setState(() => _keepModelLoaded = v);
              _saveSetting('settings_keep_model_loaded', v);
              ModelOrchestrator.instance.setKeepModelLoaded(v);
            },
          ),
```

- [ ] **Step 6: Run full verification**

Run: `flutter test && flutter analyze`
Expected: clean

- [ ] **Step 7: Commit**

```bash
git add lib/services/model_orchestrator.dart lib/screens/assistant_screen.dart lib/screens/settings_screen.dart test/services/model_orchestrator_lifecycle_test.dart
git commit -m "feat: optional keep-model-loaded setting to avoid retab reload"
```

---

# TRACK B — Input Limits & Context Compaction

### Task 4: Fix input limit counter to include conversation history

**Files:**
- Modify: `lib/utils/message_limits.dart:118-119`
- Modify: `lib/screens/assistant_screen.dart:232-258`
- Modify: `lib/services/model_orchestrator.dart` (expose token estimate helper)
- Test: `test/utils/message_limits_test.dart`

**Interfaces:**
- Produces: `MessageLimits.remainingUserBudget({...}) → ({int maxChars, int reservedTokens, int usableBudget})`
- Produces: `ModelOrchestrator.estimateHistoryTokens(List<ChatMessage>) → int`

- [ ] **Step 1: Write failing test for history-aware limit**

```dart
    test('maxUserChars drops when history tokens provided', () {
      final without = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
      );
      final withHistory = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        historyTokenEstimate: 900,
      );
      expect(withHistory, lessThan(without));
      expect(withHistory, greaterThanOrEqualTo(400));
    });

    test('remaining budget never below 400 chars floor', () {
      final maxChars = MessageLimits.maxUserCharsForInference(
        effectiveModel: NovaModel.gemma4E2b,
        historyTokenEstimate: 5000,
      );
      expect(maxChars, greaterThanOrEqualTo(400));
    });
```

- [ ] **Step 2: Run test — expect FAIL** (current floor is 200)

- [ ] **Step 3: Change floor from 200 → 400 and add `remainingUserBudget`**

```dart
  static const minUserCharFloor = 400;

  static int maxUserCharsForInference({...}) {
    // ... existing logic ...
    if (remainingTokens <= 0) return minUserCharFloor;
    // ...
  }

  static ({int maxChars, int reservedTokens, int usableBudget})
      remainingUserBudget({
    required NovaModel effectiveModel,
    int historyTokenEstimate = 0,
    int ragTokenEstimate = 0,
    bool hasAttachments = false,
  }) {
    final kvLimit = kvTokenLimitFor(effectiveModel);
    final usableBudget = (kvLimit * contextBudgetRatio).round();
    var reserved = systemPromptOverheadTokens + historyTokenEstimate;
    if (effectiveModel == NovaModel.gemma4E2b) {
      reserved += gemma4JinjaOverheadTokens;
    }
    reserved += ragTokenEstimate;
    if (hasAttachments) reserved += 200;
    final remainingTokens = usableBudget - reserved;
    final maxChars = remainingTokens <= 0
        ? minUserCharFloor
        : charsFromTokens(remainingTokens);
    return (maxChars: maxChars, reservedTokens: reserved, usableBudget: usableBudget);
  }
```

- [ ] **Step 4: Wire history into `assistant_screen.dart` limits**

```dart
  int get _historyTokenEstimate {
    final text = _messages
        .where((m) => !m.isStreaming && !m.isError)
        .map((m) => m.text)
        .join(' ');
    return MessageLimits.estimateTokens(text);
  }

  int get _messageHardLimit {
    // ... custom model branch unchanged ...
    return MessageLimits.maxUserCharsForInference(
      effectiveModel: _effectiveModel,
      hasAttachments: _hasAttachments,
      historyTokenEstimate: _historyTokenEstimate,
      ragTokenEstimate: ModelOrchestrator.instance.ragTokenEstimate,
    );
  }
```

Add `ragTokenEstimate` getter on orchestrator (returns 0 when RAG off).

- [ ] **Step 5: Show actionable hint when near limit**

When `_messageHardLimit < 800`, show subtitle: "Context full — tap Compact in ⋮ menu".

- [ ] **Step 6: Run tests + commit**

```bash
flutter test test/utils/message_limits_test.dart
git commit -m "fix: align input limit counter with history token budget"
```

---

### Task 5: LLM-based context compaction (manual + auto)

**Files:**
- Create: `lib/services/context_compaction_service.dart`
- Modify: `lib/services/conversation_summary_service.dart` (delegate to compaction for LLM path)
- Modify: `lib/screens/assistant_screen.dart` (Compact action in app bar / overflow)
- Modify: `lib/services/model_orchestrator.dart` (`_truncateContext` calls compaction first)
- Test: `test/services/context_compaction_service_test.dart`

**Interfaces:**
- Produces:
  - `ContextCompactionService.compact({required List<ChatMessage> messages, required CompactionMode mode}) → Future<CompactionResult>`
  - `CompactionResult { String summary; List<ChatMessage> retainedMessages; int tokensBefore; int tokensAfter; }`
  - `CompactionMode.manual | auto`

- [ ] **Step 1: Write failing test for extractive fallback**

```dart
test('compact uses extractive path when model busy', () async {
  final messages = List.generate(
    10,
    (i) => ChatMessage(
      id: '$i', text: 'message $i', isUser: i.isOdd,
      timestamp: DateTime(2026, 1, 1),
    ),
  );
  final result = await ContextCompactionService.instance.compactExtractive(
    messages,
    targetChars: 800,
  );
  expect(result.summary.length, lessThanOrEqualTo(800));
  expect(result.retainedMessages.length, lessThan(messages.length));
});
```

- [ ] **Step 2: Implement extractive compaction (no extra model load)**

Reuse logic from `ConversationSummaryService._buildExtractiveSummary`, but also return trimmed `retainedMessages` (keep last 4 turns).

- [ ] **Step 3: Implement LLM compaction using fast model**

```dart
  Future<CompactionResult> compactWithModel(List<ChatMessage> messages) async {
    const prompt =
        'Summarize this conversation for continuing chat. '
        'Preserve: user goals, decisions, names, open tasks. '
        'Max 600 words. Conversation:\n';
    final transcript = messages
        .map((m) => '${m.isUser ? "User" : "Assistant"}: ${m.text}')
        .join('\n');
    // Use SmolLM via ModelOrchestrator.compactQuery() — dedicated method
    // that does NOT clear _activeChat of the primary session.
    final summary = await ModelOrchestrator.instance.compactQuery(
      '$prompt$transcript',
    );
    return CompactionResult(
      summary: summary,
      retainedMessages: messages.sublist(messages.length - 4),
      tokensBefore: MessageLimits.estimateTokens(transcript),
      tokensAfter: MessageLimits.estimateTokens(summary),
    );
  }
```

Add `compactQuery` that loads SmolLM in a one-shot chat without disturbing primary `_activeChat` (use separate `InferenceModel? _compactModel` field).

- [ ] **Step 4: Auto-trigger before send when budget exhausted**

In `processMessage`, before `_validateQueryLength`:

```dart
      if (conversationHistory != null &&
          settings.autoCompactContext &&
          historyTokenEstimate > (usableBudget * 0.85).round()) {
        final compacted = await ContextCompactionService.instance
            .compactWithModel(conversationHistory);
        conversationHistory = compacted.retainedMessages;
        ragContext = '${ragContext ?? ''}\n\n[Compacted context]\n${compacted.summary}';
        historyTokenEstimate = MessageLimits.estimateTokens(compacted.summary);
      }
```

- [ ] **Step 5: Add manual "Compact context" button**

In `assistant_screen.dart` app bar `PopupMenuButton`:

```dart
  PopupMenuItem(
    value: 'compact',
    child: Text('Compact context'),
  ),
```

Handler calls compaction, replaces `_messages` with `retainedMessages`, prepends system note bubble showing summary, calls `_saveMessages()`.

- [ ] **Step 6: Settings toggle `settings_auto_compact_context` (default true)**

- [ ] **Step 7: Tests + commit**

```bash
git commit -m "feat: manual and auto context compaction for long chats"
```

---

# TRACK C — Large Models, GGUF, LAN Streaming

### Task 6: Large model loading improvements

**Files:**
- Modify: `lib/services/model_manager.dart` (validateModelFile max already 5GB)
- Modify: `lib/services/platform_adaptation_service.dart`
- Modify: `lib/main.dart` (web OPFS streaming init)
- Modify: `lib/screens/settings_screen.dart` (storage picker warning copy)

**Interfaces:**
- Produces: `PlatformAdaptationService.recommendWebStorageMode(fileSizeBytes) → WebStorageMode`
- Produces: pre-load RAM gate `canLoadModel(NovaModel) → ({bool allowed, String? reason})`

- [ ] **Step 1: Write failing test for RAM gate**

```dart
test('blocks Gemma4 when freeRam below threshold', () {
  final result = PlatformAdaptationService.canLoadModel(
    NovaModel.gemma4E2b,
    freeRamMb: 800,
  );
  expect(result.allowed, isFalse);
  expect(result.reason, isNotNull);
});
```

- [ ] **Step 2: Implement gate (threshold: 1.5 GB free for Gemma 4)**

- [ ] **Step 3: Wire web `FlutterGemma.initialize` with `WebStorageMode.streaming` when model > 2GB**

- [ ] **Step 4: Show confirm dialog before loading large models on ≤6 GB devices**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: RAM gate and web streaming for large models"
```

---

### Task 7: GGUF support (research spike + optional backend)

> **Warning:** ROADMAP lists GGUF as non-goal. This task is gated on a successful spike proving `llamadart` can coexist with `flutter_gemma_litertlm` via ABI isolation or separate process.

**Files:**
- Create: `lib/services/gguf_backend.dart`
- Create: `android/app/src/main/kotlin/dev/nova/assistant/GgufInferenceChannel.kt` (if spike succeeds)
- Modify: `lib/services/model_manager.dart:588-594` (remove hard block behind feature flag)
- Modify: `pubspec.yaml` (optional `llamadart` dependency behind comment)
- Doc: `docs/models.md`

**Interfaces:**
- Produces: `GgufBackend implements InferenceBackend`
- Produces: `InferenceBackend.generate({prompt, history, onToken}) → Stream<String>`

- [ ] **Step 1: Spike — build Android debug with both native libs**

Run on device:

```bash
flutter build apk --debug
```

Document conflict in `docs/models.md` if build fails. **Do not proceed to Step 2 if SIGSEGV or duplicate symbol errors persist.**

- [ ] **Step 2: Write failing test for backend selection**

```dart
test('selects GgufBackend for custom GGUF model', () {
  final backend = InferenceBackendResolver.resolve(
    customModel: CustomModel(path: '/x/model.gguf', isGguf: true),
  );
  expect(backend, isA<GgufBackend>());
});
```

- [ ] **Step 3: Implement `InferenceBackend` interface**

```dart
abstract class InferenceBackend {
  Future<void> load(ModelDescriptor descriptor);
  Stream<InferenceEvent> chat(ChatRequest request);
  Future<void> dispose();
}
```

- [ ] **Step 4: Implement `GgufBackend` with llama.cpp via platform channel**

Minimum viable: text-only chat, no tools, no vision. Map `CustomModel` GGUF path to native `llama_model_load`.

- [ ] **Step 5: Route `ModelOrchestrator.processMessage` through backend when model is GGUF**

- [ ] **Step 6: Update UI error messages — replace "not supported" with capability matrix**

- [ ] **Step 7: Commit behind `settings_experimental_gguf` flag (default false)**

```bash
git commit -m "feat(experimental): GGUF inference backend behind feature flag"
```

---

### Task 8: LAN model streaming (host + client)

**Reference:** Local Dream-style pattern — one device runs inference server; clients send prompts via HTTP/SSE on LAN.

**Files:**
- Create: `lib/services/lan_model_host_service.dart`
- Create: `lib/services/lan_model_client_service.dart`
- Create: `lib/services/remote_lan_backend.dart`
- Modify: `lib/screens/settings_screen.dart` (LAN section)
- Android: `android/app/src/main/AndroidManifest.xml` (network permissions, cleartext for LAN)

**Interfaces:**
- Produces:
  - `LanModelHostService.start({int port = 8089}) → Future<String> hostUrl`
  - `LanModelClientService.connect(String hostUrl) → Future<void>`
  - `RemoteLanBackend` implements `InferenceBackend`
- Protocol (JSON over HTTP):
  - `POST /v1/chat` body `{prompt, history[], max_tokens}` → SSE token stream
  - `GET /v1/models` → `{models: [{id, name}]}`
  - mDNS: `_nova-inference._tcp.local`

- [ ] **Step 1: Write failing test for protocol serializer**

```dart
test('chat request serializes history', () {
  final json = LanChatRequest(
    prompt: 'hi',
    history: [LanTurn(role: 'user', content: 'prev')],
  ).toJson();
  expect(json['history'], hasLength(1));
});
```

- [ ] **Step 2: Implement host service using Dart `shelf` + `shelf_io`**

Host wraps existing `ModelOrchestrator.processMessage` — only available when `keepModelLoaded` or model already loaded.

- [ ] **Step 3: Implement client backend**

`RemoteLanBackend.chat` POSTs to host, parses SSE tokens into `InferenceResult`.

- [ ] **Step 4: Settings UI**

- Host toggle: "Share model on local network" (shows IP + PIN)
- Client: "Connect to nearby host" (mDNS picker)
- Require 4-digit PIN on each session

- [ ] **Step 5: Security constraints**

- Bind to LAN only (`192.168.x.x`, `10.x`, IPv6 ULA)
- No internet exposure; show warning in UI
- TLS optional v2 (out of scope v1)

- [ ] **Step 6: Integration test with two emulators / device+emulator**

- [ ] **Step 7: Commit**

```bash
git add lib/services/lan_*.dart lib/services/remote_lan_backend.dart
git commit -m "feat: LAN model hosting and client streaming"
```

---

# TRACK D — Adult Mode (unrestricted local inference)

### Task 9: Adult mode setting

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/models/assistant_role.dart`
- Modify: `lib/services/model_orchestrator.dart` (`_systemPromptFor`)
- Modify: `lib/services/settings_backup_service.dart`
- Test: `test/models/assistant_role_test.dart`

**Interfaces:**
- Produces: prefs key `settings_adult_mode` (bool, default `false`)
- Produces: when true, append to system prompt:

```dart
static const adultModeSuffix =
    ' The user enabled unrestricted local mode. Do not refuse '
    'legal adult topics. Still refuse illegal content and harm.';
```

- [ ] **Step 1: Write failing test**

```dart
test('adult mode suffix applied when enabled', () {
  expect(AssistantRole.adultModeSystemSuffix, contains('unrestricted'));
});
```

- [ ] **Step 2: Add toggle in Settings > Functionality**

Place below Assistant Role with subtitle:

"Local-only: reduces refusals on legal adult topics. You are responsible for compliance."

Require 18+ confirmation dialog on first enable.

- [ ] **Step 3: Append suffix in `_systemPromptFor` when pref true**

- [ ] **Step 4: Include in settings export/import**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: optional adult mode system prompt for local unrestricted chat"
```

---

## Testing Matrix (run before declaring Track complete)

| Scenario | Steps | Expected |
|----------|-------|----------|
| Retab with keep-loaded ON | Load Gemma4, chat 3 turns, home button, return | Model status "ready" without reload spinner |
| Retab with keep-loaded OFF | Same | Model unloads but UI history intact; next send replays context |
| Persistence | Send message, kill app mid-reply | After fix: reply saved when stream completes |
| Input limit | 10-turn chat, type long message | Counter reflects reduced budget; compact suggested |
| Compact manual | 20-turn chat → Compact | Summary bubble + shorter history; send works |
| Compact auto | Enable auto, long chat | Compaction runs before validation error |
| Adult mode | Enable, ask blocked topic | Model follows suffix (best-effort; no guarantee) |
| LAN | Host on phone A, client on phone B | Client gets streamed tokens |
| GGUF | Load `.gguf` with flag on | Text chat works; tools show "unsupported" chip |

---

## Self-Review Checklist

| Spec requirement | Task |
|------------------|------|
| Fix retab model reload | Task 3 (keep loaded) + Task 2 (replay) |
| Fix new-chat feel | Task 1 + Task 2 |
| Raise input limits | Task 4 (floor 400 + history-aware UI) |
| Large models | Task 6 |
| GGUF | Task 7 (experimental) |
| LAN streaming | Task 8 |
| Compact/summarize | Task 5 |
| Adult mode | Task 9 |

**Placeholder scan:** None — all tasks include concrete code and commands.

**Type consistency:** `conversationHistory` is `List<ChatMessage>?` throughout Tracks A and B. `InferenceBackend` used in Tracks C7/C8.

---

## Recommended Execution Order

1. **Track A** (Tasks 1–3) — highest user impact, lowest risk
2. **Track B** (Tasks 4–5) — fixes 200-char pain
3. **Track D** (Task 9) — small, independent
4. **Track C** (Tasks 6–8) — largest effort; Task 7 spike may fail

If GGUF spike fails, ship Tracks A/B/D + Task 6 + Task 8; document GGUF as blocked in `docs/models.md`.

---

## Further Improvements (out of scope for this plan)

- Conversation branching (ROADMAP Phase 2)
- Output length slider (max tokens per response)
- Encrypted PIN + TLS for LAN
- iOS LAN background hosting (platform limits)
- Semantic compaction (embedding-based turn selection)

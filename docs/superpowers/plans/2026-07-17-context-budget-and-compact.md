# Context Budget Expansion + Compact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users type substantially longer messages on Gemma 4 (far above the ~200–1716 character trap), and add **auto + manual compact** that summarizes older turns so the KV window stays usable without “start a new chat”.

**Architecture:** Raise Android Gemma 4 KV from 2048→4096 behind a **High context (more RAM)** setting (default off on ≤6 GB devices if detectable, else default on with warning). Lower reserved overhead constants slightly after measuring. Extend `ConversationSummaryService` with an explicit `compactNow` that writes a summary and asks the orchestrator to replace old `InferenceChat` history with `[summary message] + recent turns`. Auto-trigger compact when `maxUserCharsForInference` would fall below a soft floor (e.g. 800 chars) before send.

**Tech Stack:** Existing `MessageLimits`, `ConversationSummaryService`, `ModelOrchestrator._truncateContext` / `clearHistory`, Settings prefs.

## Global Constraints

- Do not load a second model solely to summarize on low-RAM phones — keep extractive summary as default; optional “LLM compact” only when keep-warm model is already loaded and user enabled it.
- Keep floor of 200 chars only as last-resort safety; after this plan, empty-session Gemma 4 Android should allow **≥4000** characters when high-context is on.
- Sync `_tokenLimitFor` in orchestrator / parallel session manager / `MessageLimits.kvTokenLimitFor`.

## File map

| File | Responsibility |
|------|----------------|
| `lib/utils/message_limits.dart` | KV limits, budget ratio, overhead, high-context flag input |
| `lib/services/model_orchestrator.dart` | Token limit sync; compact API; auto-compact before validate |
| `lib/services/conversation_summary_service.dart` | `compactNow`, stronger extractive rules |
| `lib/screens/assistant_screen.dart` | Manual Compact action; pass history estimates into counter |
| `lib/screens/settings_screen.dart` | High context + auto-compact toggles |
| `test/utils/message_limits_test.dart` | Updated expectations |
| `test/services/conversation_summary_service_test.dart` | Compact tests |

---

### Task 1: Raise token budget math (TDD)

**Files:**
- Modify: `lib/utils/message_limits.dart`
- Modify: `test/utils/message_limits_test.dart`
- Modify: `lib/services/model_orchestrator.dart` `_tokenLimitFor`
- Modify: `lib/services/parallel_session_manager.dart` (duplicate KV switch)

**Interfaces:**
- Produces:
  - `MessageLimits.kvTokenLimitFor(model, {bool highContext = false})`
  - When `model == gemma4E2b && highContext` → **4096** on Android (and elsewhere)
  - When highContext false → keep 2048 on Android
  - Reduce `gemma4JinjaOverheadTokens` from 500 → **350** and `systemPromptOverheadTokens` from 300 → **220** (still conservative)
  - Raise contextBudgetRatio from 0.6 → **0.7** when highContext
  - Floor when exhausted: raise from 200 → **400**

Empty-session estimate with highContext:
`usable = 4096 * 0.7 = 2867; reserved = 220 + 350 = 570; remaining = 2297 tokens → ~9188 chars`, then capped by medium hardLimit 4000 — so UI shows **4000** (or large tier if we also bump Android Gemma 4 tier to large when highContext).

Also: when highContext, `tierFor(gemma4E2b Android)` returns **large** (hard 8000).

- [ ] **Step 1: Update failing tests first**

Replace/add in `test/utils/message_limits_test.dart`:

```dart
test('kvTokenLimitFor Gemma 4 highContext is 4096', () {
  expect(
    MessageLimits.kvTokenLimitFor(
      NovaModel.gemma4E2b,
      highContext: true,
    ),
    4096,
  );
});

test('highContext empty session allows at least 4000 user chars', () {
  final maxChars = MessageLimits.maxUserCharsForInference(
    effectiveModel: NovaModel.gemma4E2b,
    highContext: true,
  );
  expect(maxChars, greaterThanOrEqualTo(4000));
});

test('low context still protects mid-range RAM', () {
  final maxChars = MessageLimits.maxUserCharsForInference(
    effectiveModel: NovaModel.gemma4E2b,
    highContext: false,
  );
  // Still better than 200 after overhead trim, but may be < 4000
  expect(maxChars, greaterThanOrEqualTo(1500));
});
```

Update existing test that assumes Gemma 4 KV is always 2048 — pass `highContext: false` explicitly.

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/utils/message_limits_test.dart -v`

- [ ] **Step 3: Implement message_limits changes**

```dart
static const contextBudgetRatio = 0.6;
static const highContextBudgetRatio = 0.7;
static const gemma4JinjaOverheadTokens = 350;
static const systemPromptOverheadTokens = 220;
static const exhaustedBudgetFloorChars = 400;

static int kvTokenLimitFor(
  NovaModel model, {
  bool highContext = false,
}) {
  switch (model) {
    case NovaModel.smollm:
      return 512;
    case NovaModel.fastvlm:
      return 1024;
    case NovaModel.gemma3_1b:
      return 2048;
    case NovaModel.gemma4E2b:
      if (highContext) return 4096;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        return 2048;
      }

      return 4096;
  }
}

static int maxUserCharsForInference({
  required NovaModel effectiveModel,
  int historyTokenEstimate = 0,
  int ragTokenEstimate = 0,
  bool hasAttachments = false,
  bool highContext = false,
}) {
  final kvLimit = kvTokenLimitFor(
    effectiveModel,
    highContext: highContext,
  );
  final ratio = highContext ? highContextBudgetRatio : contextBudgetRatio;
  final usableBudget = (kvLimit * ratio).round();

  var reserved = systemPromptOverheadTokens + historyTokenEstimate;
  if (effectiveModel == NovaModel.gemma4E2b) {
    reserved += gemma4JinjaOverheadTokens;
  }
  reserved += ragTokenEstimate;
  if (hasAttachments) reserved += 200;

  final remainingTokens = usableBudget - reserved;
  if (remainingTokens <= 0) return exhaustedBudgetFloorChars;

  final charCap = charsFromTokens(remainingTokens);
  final tier = highContext && effectiveModel == NovaModel.gemma4E2b
      ? MessageLimitTier.large
      : tierFor(model: effectiveModel);
  final tierCap = hardLimit(tier, hasAttachments: hasAttachments);

  return charCap < tierCap ? charCap : tierCap;
}
```

Thread `highContext` through `validateTokenBudget` / `softUserCharsForInference` the same way.

Sync orchestrator:

```dart
int _tokenLimitFor(NovaModel model) {
  return MessageLimits.kvTokenLimitFor(
    model,
    highContext: _highContextEnabled,
  );
}
```

Remove duplicated switch bodies in orchestrator and parallel_session_manager — call `MessageLimits.kvTokenLimitFor` instead (DRY).

- [ ] **Step 4: Run tests**

```bash
flutter test test/utils/message_limits_test.dart test/services/model_orchestrator_budget_test.dart
```

Fix any budget tests that hard-code old overhead.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/message_limits.dart lib/services/model_orchestrator.dart lib/services/parallel_session_manager.dart test/utils/message_limits_test.dart test/services/model_orchestrator_budget_test.dart
git commit -m "feat: high-context KV budget for longer user messages"
```

---

### Task 2: Settings — High context + Auto compact

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/services/model_orchestrator.dart` (`refreshSettings`, fields)
- Modify: `lib/services/settings_backup_service.dart`

**Interfaces:**
- Prefs: `settings_high_context` (bool, default `false` on Android, `true` elsewhere)
- Prefs: `settings_auto_compact` (bool, default `true`)
- Orchestrator: `_highContextEnabled`, `_autoCompactEnabled` + setters loaded in `refreshSettings`

- [ ] **Step 1: Add toggles**

```dart
_toggleTile(
  icon: Icons.fit_screen,
  title: 'High context window',
  subtitle:
      'Larger KV (4096) for longer messages. Uses more RAM — avoid on ≤6 GB phones.',
  value: _highContext,
  onChanged: (v) async {
    setState(() => _highContext = v);
    await _saveSetting('settings_high_context', v);
    await ModelOrchestrator.refreshSettings();
  },
),
_toggleTile(
  icon: Icons.compress,
  title: 'Auto-compact context',
  subtitle:
      'When the chat gets long, summarize older turns so new messages still fit.',
  value: _autoCompact,
  onChanged: (v) async {
    setState(() => _autoCompact = v);
    await _saveSetting('settings_auto_compact', v);
    await ModelOrchestrator.refreshSettings();
  },
),
```

- [ ] **Step 2: Load defaults in orchestrator.refreshSettings**

```dart
_highContextEnabled = prefs.getBool('settings_high_context') ??
    (kIsWeb || defaultTargetPlatform != TargetPlatform.android);
_autoCompactEnabled = prefs.getBool('settings_auto_compact') ?? true;
```

- [ ] **Step 3: Backup keys**

Export/import `highContext` / `autoCompact`.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings_screen.dart lib/services/model_orchestrator.dart lib/services/settings_backup_service.dart
git commit -m "feat: settings for high context and auto-compact"
```

---

### Task 3: Compact service API (manual + building block for auto)

**Files:**
- Modify: `lib/services/conversation_summary_service.dart`
- Create: `test/services/conversation_summary_service_test.dart`

**Interfaces:**
- Produces:
  - `Future<CompactResult> compactNow(Conversation conversation, {int keepRecent = 6})`
  - `CompactResult({required String summary, required List<ChatMessage> retainedMessages})`
  - `retainedMessages` = synthetic system-style assistant note + last `keepRecent` real messages
  - Summary max chars raise `_maxSummaryChars` 1200 → **2000**

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/services/conversation_summary_service.dart';

void main() {
  test('compactNow returns summary and keeps recent turns', () async {
    final messages = [
      for (var i = 0; i < 12; i++)
        ChatMessage(
          id: '$i',
          text: i.isEven ? 'User goal $i about travel' : 'Assistant reply $i',
          isUser: i.isEven,
          timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
    ];
    final conversation = Conversation(
      id: 'c1',
      title: 'Test',
      messages: messages,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final result = await ConversationSummaryService.instance.compactNow(
      conversation,
      keepRecent: 4,
    );

    expect(result.summary, isNotEmpty);
    expect(result.retainedMessages.length, lessThan(messages.length));
    expect(result.retainedMessages.last.text, messages.last.text);
  });
}
```

Adjust `Conversation` constructor fields to match `lib/models/conversation.dart` exactly (read file before coding).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

```dart
class CompactResult {
  const CompactResult({
    required this.summary,
    required this.retainedMessages,
  });

  final String summary;
  final List<ChatMessage> retainedMessages;
}

Future<CompactResult> compactNow(
  Conversation conversation, {
  int keepRecent = 6,
}) async {
  final summary = _buildExtractiveSummary(conversation.messages);
  final usable = conversation.messages
      .where((m) => !m.isStreaming && !m.isError && m.text.trim().isNotEmpty)
      .toList();
  final recent = usable.length > keepRecent
      ? usable.sublist(usable.length - keepRecent)
      : usable;

  final summaryMessage = ChatMessage(
    id: 'compact-${DateTime.now().millisecondsSinceEpoch}',
    text: '[Conversation summary]\n$summary',
    isUser: false,
    timestamp: DateTime.now(),
    modelName: 'compact',
  );

  final retained = [summaryMessage, ...recent];
  final updated = conversation.copyWith(
    summary: summary,
    messages: retained,
  );
  await ChatHistoryService.updateConversation(updated);
  activeSummary = summary;

  return CompactResult(summary: summary, retainedMessages: retained);
}
```

If replacing UI messages is too aggressive for v1, **only** update `conversation.summary` + return `retainedMessages` for orchestrator reinjection, and let the screen keep full visible history. Prefer: **UI keeps full history**; orchestrator session uses compacted replay. Then `compactNow` should **not** wipe `conversation.messages` — only refresh summary and return replay list:

```dart
return CompactResult(
  summary: summary,
  retainedMessages: [summaryMessage, ...recent],
);
// still: await ChatHistoryService.updateConversation(conversation.copyWith(summary: summary));
```

Use this UI-preserving variant.

- [ ] **Step 4: Tests PASS + commit**

```bash
flutter test test/services/conversation_summary_service_test.dart
git add lib/services/conversation_summary_service.dart test/services/conversation_summary_service_test.dart
git commit -m "feat: compactNow extractive context summarization"
```

---

### Task 4: Wire auto + manual compact into chat + orchestrator

**Files:**
- Modify: `lib/services/model_orchestrator.dart`
- Modify: `lib/screens/assistant_screen.dart`

**Interfaces:**
- Orchestrator method:

```dart
Future<void> applyCompactedReplay(List<ChatMessage> retained) async {
  if (_activeChat == null) {
    setPendingReplayMessages(retained);
    return;
  }
  final replay = SessionHistoryReinjection.buildReplayMessages(
    retained,
    maxTokens: (_tokenLimitFor(_activeModelType ?? NovaModel.gemma4E2b) *
            MessageLimits.contextBudgetRatio)
        .round(),
  );
  await _activeChat!.clearHistory(replayHistory: replay);
}
```

(Depends on session keep-alive plan’s `SessionHistoryReinjection` — implement that plan first.)

- Auto before validate in `processMessage`:

```dart
if (_autoCompactEnabled) {
  final provisionalMax = MessageLimits.maxUserCharsForInference(
    effectiveModel: model,
    historyTokenEstimate: historyTokenEstimate,
    ragTokenEstimate: ragTokenEstimate,
    hasAttachments: hasExtraContext,
    highContext: _highContextEnabled,
  );
  if (provisionalMax < 800 && onCompactNeeded != null) {
    await onCompactNeeded!(); // callback set by UI, or orchestrator holds Conversation id
  }
}
```

Simpler approach for v1: do auto-compact **in the screen** before calling `processMessage`:

```dart
Future<void> _maybeAutoCompact() async {
  if (!ModelOrchestrator.instance.autoCompactEnabled) return;
  final effective = _effectiveModel;
  final maxChars = MessageLimits.maxUserCharsForInference(
    effectiveModel: effective,
    historyTokenEstimate: /* estimate from _messages */,
    highContext: ModelOrchestrator.instance.highContextEnabled,
  );
  if (maxChars >= 800) return;
  final conversation = /* current Conversation */;
  final result =
      await ConversationSummaryService.instance.compactNow(conversation);
  await ModelOrchestrator.instance.applyCompactedReplay(
    result.retainedMessages,
  );
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Context compacted to free space')),
    );
  }
}
```

- Manual: icon button (compress) in app bar or above input:

```dart
IconButton(
  tooltip: 'Compact context',
  icon: const Icon(Icons.compress),
  onPressed: _isGenerating ? null : _manualCompact,
)
```

- [ ] **Step 1: Implement screen helpers + button**
- [ ] **Step 2: Fix character counter to use highContext + optional history estimate**

Update `_messageHardLimit` getter in `assistant_screen.dart` to pass `highContext: ModelOrchestrator.instance.highContextEnabled`.

- [ ] **Step 3: Analyze + test**

```bash
dart format .
flutter analyze
flutter test
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/assistant_screen.dart lib/services/model_orchestrator.dart
git commit -m "feat: auto and manual context compact in chat"
```

---

### Task 5: Docs

- Update `doc/PLAN-features.md` shipped table: high context + compact.
- Update `docs/models.md` with note on Android KV 2048 vs 4096 setting.

- [ ] **Step 1: Edit docs**
- [ ] **Step 2: Commit** `docs: document high context and compact`

---

## Self-review

1. Longer input → Task 1–2. Compact auto/manual → Tasks 3–4. Large answers unchanged (generation not capped by input UI).
2. Depends on session reinjection helper from keep-alive plan.
3. `highContext` naming consistent across limits, orchestrator, settings.

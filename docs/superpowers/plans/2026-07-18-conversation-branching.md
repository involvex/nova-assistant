# Conversation Branching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From any message bubble, fork a **new conversation** that keeps history up through that message, leaves the original chat intact, and opens the branch ready for a new turn.

**Architecture:** Do **not** build a message DAG. Nova already stores a flat `List<ChatMessage>` per `Conversation`. Branching = copy prefix messages into a new `Conversation` (new ids), optional provenance fields (`branchedFromId`, `branchedFromMessageId`), then navigate to that conversation and reset inference history to the prefix (same reinjection path as keep-alive). Edit / regenerate stay as **in-place truncate**; Branch is the non-destructive alternative.

**Tech Stack:** Flutter, existing `Conversation` / `ChatMessage` / `ChatHistoryService`, `AssistantScreen(conversationId:)`, `SessionHistoryReinjection`, `uuid`.

## Global Constraints

- Prefer on-device; no new cloud deps.
- Screenshots stay non-persisted (`[Screenshot]` placeholder) — branch copies persisted shape only.
- Respect `ChatHistoryService` caps: max **40** conversations, **200** messages each, **4 MB** file.
- Android parallel sessions remain capped at 1 — branching navigates to a new screen, does not require concurrent models.
- After branch open, inference must see the prefix (reinject / clear+replay), not the discarded original tail.
- Conventional commits; `dart format`, `flutter analyze`, `flutter test` before merge.
- Do not implement share-sheet polish or dictation in this PR (separate plans below).

## File map

| File | Responsibility |
|------|----------------|
| `lib/models/conversation.dart` | Optional `branchedFromId` / `branchedFromMessageId`; JSON round-trip |
| `lib/services/conversation_branching.dart` | Pure: prefix slice + new conversation factory |
| `lib/services/chat_history_service.dart` | `branchFromMessage(...)` persist helper (thin wrap) |
| `lib/widgets/chat_bubble.dart` | `onBranch` action next to Edit / Regenerate |
| `lib/screens/assistant_screen.dart` | Wire branch → create → navigate / replace |
| `lib/screens/chat_history_screen.dart` | Optional “Branched” subtitle / badge |
| `test/services/conversation_branching_test.dart` | Pure unit tests |
| `doc/PLAN-features.md` / `docs/models.md` N/A | Update PLAN when shipped |

## Product behavior (acceptance)

1. On a **user** or **assistant** bubble (not streaming / empty), show **Branch**.
2. Branch creates a **new** conversation titled like `Branch: <preview>` (or `Branched from <title>`).
3. New conversation messages = original `[0 .. index]` inclusive (same text/metadata; **new message ids**).
4. Original conversation unchanged (contrast: Edit/Regenerate truncate in place).
5. App opens the new conversation; user can send immediately; model context matches the prefix.
6. History list shows the new chat; optional badge “Branched”.
7. Works after app restart (persisted via `conversations.json`).

## Non-goals (this plan)

- In-tree alternate replies / side-by-side branch UI / merge branches.
- Changing Edit or Regenerate semantics.
- Share sheet polish, continuous dictation, on-device image gen.

## Architecture notes (codebase survey)

Survey: [Explore chat branching](0414a2cb-ca80-48a6-bdba-ef8b15690b8f).

- **No DAG today** — `ChatMessage` / `Conversation` are linear; edit/regen already
  `removeRange(index, end)` then `setPendingReplayMessages` on next send
  (`assistant_screen.dart` ~623–691, ~805–807).
- **Reuse** `ModelOrchestrator.setPendingReplayMessages` +
  `SessionHistoryReinjection` — do **not** invent a second replay path.
- **Id-scoped APIs only** — never `ChatHistoryService.save` / `load` (legacy
  first-conversation-only) when forking.
- **New message ids must be UUIDs** — UI still often uses epoch strings; branches
  must not collide under rapid fork.
- **Summary policy:** copy `source.summary` onto the branch only if the branch
  prefix length is ≥ the summary’s implied coverage; otherwise set `summary: null`
  and let `maybeUpdateSummary` rebuild. Do not share mutable orchestrator
  `activeSummary` across screens.
- **Beginner UI:** `assistant_screen_beginner.dart` currently wires regenerate
  only — add Branch there too or document expert-only for v1 (prefer both).
- **Risk:** UI truncate ≠ live `_activeChat` KV until recreate/replay; after
  navigate, force pending replay (and ideally `_activeChat = null` / identity
  clear) so the branch never sees the original tail.

---

### Task 1: Pure branching helper (TDD)

**Files:**
- Create: `lib/services/conversation_branching.dart`
- Test: `test/services/conversation_branching_test.dart`

**Interfaces:**
- Consumes: `Conversation`, `ChatMessage`
- Produces:
  - `Conversation branchConversation({required Conversation source, required int messageIndex, DateTime? now})`
  - Throws / returns null if `messageIndex` out of range or message is streaming
  - Copies prefix `0..messageIndex` with **new UUID** message ids and new conversation id
  - Sets `branchedFromId = source.id`, `branchedFromMessageId = source.messages[messageIndex].id`
  - Title: `Branch: ${source.previewTitle}` truncated to ~50 chars
  - Default `summary: null` on branch (safer than copying a summary that covers dropped turns)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';
import 'package:nova_assistant/models/conversation.dart';
import 'package:nova_assistant/services/conversation_branching.dart';

void main() {
  test('branch copies prefix and preserves source', () {
    final source = Conversation(
      id: 'src',
      title: 'Trip planning',
      messages: [
        ChatMessage(id: 'u1', text: 'Hi', isUser: true, timestamp: DateTime(2026, 1, 1)),
        ChatMessage(id: 'a1', text: 'Hello', isUser: false, timestamp: DateTime(2026, 1, 1, 0, 1)),
        ChatMessage(id: 'u2', text: 'Paris?', isUser: true, timestamp: DateTime(2026, 1, 1, 0, 2)),
      ],
    );

    final branch = branchConversation(source: source, messageIndex: 1);

    expect(branch.id, isNot(source.id));
    expect(branch.messages.length, 2);
    expect(branch.messages.map((m) => m.text), ['Hi', 'Hello']);
    expect(branch.messages.every((m) => m.id != 'u1' && m.id != 'a1'), isTrue);
    expect(branch.branchedFromId, 'src');
    expect(branch.branchedFromMessageId, 'a1');
    expect(source.messages.length, 3); // untouched
  });
}
```

- [ ] **Step 2: Run test — expect fail** (missing API / fields)
- [ ] **Step 3: Implement minimal `branchConversation` + Conversation fields**
- [ ] **Step 4: Run tests — pass**
- [ ] **Step 5: Commit** `test: add conversation branching helper coverage`

---

### Task 2: Persist provenance on Conversation

**Files:**
- Modify: `lib/models/conversation.dart`
- Modify: `test/services/conversation_branching_test.dart` (JSON round-trip)

**Interfaces:**
- Add optional `String? branchedFromId`, `String? branchedFromMessageId`
- `copyWith` / `toJson` / `fromJson` (omit nulls or store null-safe)

- [ ] **Step 1: Extend model + round-trip test**
- [ ] **Step 2: Implement**
- [ ] **Step 3: `flutter test test/services/conversation_branching_test.dart`**
- [ ] **Step 4: Commit** `feat: track conversation branch provenance`

---

### Task 3: ChatHistoryService.branchFromMessage

**Files:**
- Modify: `lib/services/chat_history_service.dart`
- Test: `test/services/chat_history_export_test.dart` or new file using existing fake path provider

**Interfaces:**
- `static Future<Conversation> branchFromMessage({required String conversationId, required int messageIndex})`
- Load source → `branchConversation` → prepend via existing save path (`create`/`saveConversations`)
- If at conversation cap (40), drop oldest non-source conversation (existing `_capConversations` behavior is enough if we insert then cap)

- [ ] **Step 1: Failing test — branch persists and source unchanged**
- [ ] **Step 2: Implement service method**
- [ ] **Step 3: Tests pass**
- [ ] **Step 4: Commit** `feat: persist branched conversations`

---

### Task 4: Bubble + AssistantScreen wiring

**Files:**
- Modify: `lib/widgets/chat_bubble.dart` — add `VoidCallback? onBranch`, action label `Branch`
- Modify: `lib/screens/assistant_screen.dart` — `_branchFromMessage(int index)`
- Modify: `lib/screens/assistant_screen_beginner.dart` if it mirrors bubble actions

**Behavior:**
```dart
Future<void> _branchFromMessage(int index) async {
  if (_isGenerating || _conversationId == null) return;
  final branched = await ChatHistoryService.branchFromMessage(
    conversationId: _conversationId!,
    messageIndex: index,
  );
  ModelOrchestrator.instance.setPendingReplayMessages(branched.messages);
  // Ensure next screen does not reuse KV that still holds the original tail.
  // Prefer existing teardown / clearActiveInferenceIdentity patterns over a
  // new API — mirror compact / edit replay behavior.
  if (!mounted) return;
  await Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => AssistantScreen(conversationId: branched.id),
    ),
  );
}
```

- Guard: disable while streaming; skip if message `isStreaming`.
- Snackbar optional: `Branched conversation created`.
- Wire **both** `assistant_screen.dart` and `assistant_screen_beginner.dart`.

- [ ] **Step 1: Add `onBranch` to bubble (UI only)**
- [ ] **Step 2: Wire handler + navigation**
- [ ] **Step 3: Manual checklist on emulator / F1 with SmolLM**
- [ ] **Step 4: Commit** `feat: branch conversation from message bubble`

---

### Task 5: History list affordance

**Files:**
- Modify: `lib/screens/chat_history_screen.dart`

- [ ] **Step 1: If `branchedFromId != null`, show muted subtitle `Branched` (or arrow from parent title if cheap to resolve)**
- [ ] **Step 2: Commit** `feat: show branched badge in chat history`

---

### Task 6: Docs + PLAN checkbox

**Files:**
- Modify: `doc/PLAN-features.md` — mark branching shipped / link plan
- Modify: `docs/superpowers/plans/2026-07-18-README.md` (index for this slate)

- [ ] **Step 1: Update living plan**
- [ ] **Step 2: Commit** `docs: mark conversation branching plan`

---

## Verification (device)

- [ ] Branch from mid-thread user message → new chat has prefix only; original intact
- [ ] Branch from assistant message → includes that assistant turn
- [ ] Send in branch → coherent reply (reinjection worked)
- [ ] Kill app → both conversations still in history
- [ ] Edit/Regenerate still truncate in place (unchanged)

## Follow-on slate (separate plans — do not mix into this PR)

| Order | Feature | Plan file | Note |
|-------|---------|-----------|------|
| Next | Share message / chat sheet polish | `2026-07-18-share-sheet-polish.md` (write when branching ships) | Build on `ExportService.shareText` + per-bubble share |
| Then | Continuous dictation / audio attach | `2026-07-18-dictation-audio.md` | Extend `voice_input.dart`; no auto-send until listen ends (already fixed) |
| Ongoing | Heavy models / image gen | existing LAN + `docs/models.md` | Gemma 4 / diffusion on **X8 Pro Max soak** or **LAN remote**; not F1 |

## Suggested PR title

`feat: branch conversations from a message without destroying the original`

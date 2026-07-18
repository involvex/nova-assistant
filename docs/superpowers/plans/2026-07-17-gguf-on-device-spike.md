# On-Device GGUF Spike (Deferred) Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a **research spike + decision record**, not a production feature. Decide whether on-device GGUF can ever coexist with `flutter_gemma_litertlm` on Android, or whether LAN remote inference remains the only supported GGUF path.

**Architecture:** Time-boxed investigation. Current code already stubs GGUF (`ModelOrchestrator._processGgufModel`) and blocks install. `doc/PLAN-features.md` lists “Shipping GGUF inference” as an **explicit non-goal**. This plan exists so engineers do not re-litigate the decision without evidence.

**Tech Stack:** Android NDK, possible `llama.cpp` / `llamadart`, existing LiteRtLm / MediaPipe plugins.

## Global Constraints

- Do **not** merge GGUF inference into `main` from this plan.
- Do **not** add `llamadart` to `pubspec.yaml` on the product branch until the spike ADR says go.
- Prefer LAN remote inference plan for user-facing GGUF needs.

## File map (spike artifacts only)

| File | Responsibility |
|------|----------------|
| `docs/superpowers/spikes/gguf-on-device-adr.md` | Architecture Decision Record |
| Optional throwaway branch `spike/gguf-native-6c1a` | Experiments — never required to merge |

---

### Task 1: Document current blockers

- [ ] **Step 1: Collect evidence from repo**

Quote and link:
- `lib/services/model_orchestrator.dart` `_processGgufModel` error text about llamadart vs LiteRtLm native libs
- `lib/services/model_manager.dart` install rejection for `.gguf`
- `doc/PLAN-features.md` Explicit non-goals
- UI still listing `.gguf` in settings pickers (inconsistency)

- [ ] **Step 2: Write ADR skeleton**

Create `docs/superpowers/spikes/gguf-on-device-adr.md`:

```markdown
# ADR: On-device GGUF in Nova

## Status
Proposed (spike)

## Context
Users want GGUF. Nova ships LiteRtLm + MediaPipe via flutter_gemma.

## Options
1. Keep non-goal; use LAN remote inference for GGUF
2. Separate APK flavor: `gguf` vs `litert` (mutually exclusive native libs)
3. Separate process / isolated service loading only llama.cpp
4. Wait for a flutter_gemma backend that speaks GGUF

## Decision
Default until spike proves otherwise: **Option 1** (LAN remote for GGUF).
Update this section after Tasks 2–3 with evidence.

## Consequences
...
```

- [ ] **Step 3: Commit** `docs: start GGUF on-device ADR spike`

---

### Task 2: Native conflict reproduction (optional machine work)

- [ ] **Step 1: On a throwaway branch**, attempt adding a minimal llama.cpp Android AAR **without** shipping UI
- [ ] **Step 2: Record** load failures / `.so` clashes / duplicate JNI with LiteRtLm
- [ ] **Step 3: Append findings to ADR (commands, logcat snippets, conclusions)
- [ ] **Step 4: Commit on spike branch only**

If no device/NDK available, mark Task 2 skipped and recommend Option 1 in ADR.

---

### Task 3: Product decision

- [ ] **Step 1: Choose option** (default recommendation: **Option 1** — LAN remote — until Option 2/3 proven)
- [ ] **Step 2: If Option 1:** ensure settings UI **stops advertising** installable `.gguf` for on-device (small follow-up PR): remove `.gguf` from `allowedExtensions` in settings / show “Use Remote LAN” deep link
- [ ] **Step 3: Update `doc/PLAN-features.md` non-goals with pointer to ADR + LAN plan
- [ ] **Step 4: Commit** `docs: record GGUF decision; point to LAN remote plan`

---

### Task 4: UX honesty fix (allowed even if GGUF stays non-goal)

**Files:**
- `lib/screens/settings_screen.dart`
- `lib/widgets/custom_model_import_sheet.dart` (if present)

- [ ] **Step 1: When user picks `.gguf`, show dialog:**

```dart
'On-device GGUF is not supported. Use Settings → Remote LAN inference '
'with llama-server hosting your .gguf file.'
```

- [ ] **Step 2: Commit** `fix: stop implying on-device GGUF install works`

---

## Self-review

1. User ask “can we support gguf” → answered via ADR + LAN path, not a fake half-integration.
2. No production llamadart dependency from this plan.
3. UX honesty task removes the current picker/install contradiction.

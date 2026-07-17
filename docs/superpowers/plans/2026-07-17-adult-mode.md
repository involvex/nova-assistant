# Adult Mode Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first **Adult mode** setting that steers the on-device system prompt so the assistant does not apply extra prudish refusals for legal adult topics. No cloud moderation; user-controlled; clearly labeled.

**Architecture:** Boolean pref `settings_adult_mode` (default `false`). When enabled, `_systemPromptFor` appends a short policy suffix. Optional confirmation dialog on first enable. No separate content filter exists today — Gemma may still refuse some topics based on its own weights; adult mode only removes *app-imposed* steer toward refusal and adds explicit allow language.

**Tech Stack:** SharedPreferences, `ModelOrchestrator._systemPromptFor`, Settings UI `_toggleTile`, backup service.

## Global Constraints

- Default **off**.
- Copy must stay clear: this does not unlock illegal content; it reduces unnecessary refusals for adult sexual topics between consenting adults.
- Do not log user prompts related to this setting.
- Works with identity override and compact Android prompts (append short suffix even in compact mode).

## File map

| File | Responsibility |
|------|----------------|
| `lib/models/adult_mode_policy.dart` | Prompt suffix + confirmation copy (single source) |
| `lib/services/model_orchestrator.dart` | Read pref; append suffix in `_systemPromptFor` |
| `lib/screens/settings_screen.dart` | Toggle + confirm dialog |
| `lib/services/settings_backup_service.dart` | Export/import |
| `test/models/adult_mode_policy_test.dart` | Unit tests for suffix |

---

### Task 1: Policy helper (TDD)

**Files:**
- Create: `lib/models/adult_mode_policy.dart`
- Test: `test/models/adult_mode_policy_test.dart`

**Interfaces:**
- Produces:
  - `static const prefsKey = 'settings_adult_mode'`
  - `static String systemPromptSuffix({required bool compact})`
  - Compact ≤ 180 chars; full ≤ 400 chars

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';

void main() {
  group('AdultModePolicy', () {
    test('prefsKey is stable', () {
      expect(AdultModePolicy.prefsKey, 'settings_adult_mode');
    });

    test('full suffix mentions adult topics and legality', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: false);
      expect(s.toLowerCase(), contains('adult'));
      expect(s.toLowerCase(), contains('illegal'));
      expect(s.length, lessThanOrEqualTo(400));
    });

    test('compact suffix is short', () {
      final s = AdultModePolicy.systemPromptSuffix(compact: true);
      expect(s.length, lessThanOrEqualTo(180));
      expect(s.toLowerCase(), contains('adult'));
    });
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `flutter test test/models/adult_mode_policy_test.dart -v`

- [ ] **Step 3: Implement**

```dart
/// Local-first adult-content steering for system prompts.
class AdultModePolicy {
  const AdultModePolicy._();

  static const prefsKey = 'settings_adult_mode';

  static String systemPromptSuffix({required bool compact}) {
    if (compact) {
      return ' Adult mode: answer legal adult sexual topics directly; '
          'refuse only illegal or non-consensual content.';
    }

    return '\n\nAdult mode is ON (local user preference). '
        'Treat the user as an adult. Answer questions about sexual topics, '
        'erotica, and adult relationships helpfully and without lecturing, '
        'shame, or unnecessary refusals. '
        'Still refuse content that is illegal or involves minors, '
        'non-consent, or real-world harm. '
        'Do not claim a cloud safety filter blocked the request — '
        'this app runs fully on-device.';
  }
}
```

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/models/adult_mode_policy.dart test/models/adult_mode_policy_test.dart
git commit -m "feat: add adult mode prompt policy helper"
```

---

### Task 2: Orchestrator wiring

**Files:**
- Modify: `lib/services/model_orchestrator.dart`

**Interfaces:**
- Field `bool _adultModeEnabled = false`
- Load in existing role/settings load + `refreshSettings`
- In `_systemPromptFor`, after building `buffer` base (and before or after RAG):

```dart
if (_adultModeEnabled) {
  buffer.write(AdultModePolicy.systemPromptSuffix(compact: compact));
}
```

Also expose `bool get adultModeEnabled` for UI if needed.

- [ ] **Step 1: Add load + append** (no separate unit test required if policy tested; optional golden string test)

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/services/model_orchestrator.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/services/model_orchestrator.dart
git commit -m "feat: inject adult mode suffix into system prompt"
```

---

### Task 3: Settings UI with confirmation

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/services/settings_backup_service.dart`

**Interfaces:**
- Toggle in Functionality (or Privacy) section
- Enabling `true` shows `AlertDialog` confirm; Cancel leaves off

- [ ] **Step 1: State + load**

```dart
bool _adultMode = false;
// load:
_adultMode = prefs.getBool(AdultModePolicy.prefsKey) ?? false;
```

- [ ] **Step 2: Toggle with dialog**

```dart
_toggleTile(
  icon: Icons.visibility_outlined,
  title: 'Adult mode',
  subtitle:
      'Allow direct answers on legal adult topics. On-device only; still refuses illegal content.',
  value: _adultMode,
  onChanged: (v) async {
    if (v) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Enable adult mode?'),
              content: const Text(
                'Nova will answer legal adult sexual topics more directly. '
                'Illegal content remains disallowed. This setting stays on your device.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    setState(() => _adultMode = v);
    await _saveSetting(AdultModePolicy.prefsKey, v);
    await ModelOrchestrator.refreshSettings();
  },
),
```

- [ ] **Step 3: Backup**

Add `adultMode` bool to assistant settings export/import.

- [ ] **Step 4: Format, analyze, test**

```bash
dart format lib/screens/settings_screen.dart lib/services/settings_backup_service.dart
flutter analyze
flutter test test/models/adult_mode_policy_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart lib/services/settings_backup_service.dart
git commit -m "feat: adult mode setting with confirmation dialog"
```

---

### Task 4: Docs

- [ ] Add shipped row in `doc/PLAN-features.md`
- [ ] One sentence in `docs/getting-started.md` or settings section if settings are documented
- [ ] Commit: `docs: document adult mode setting`

---

## Self-review

1. Adult mode request covered; illegal content still refused in copy.
2. Compact Android path still gets a short suffix.
3. Prefs key `settings_adult_mode` consistent.

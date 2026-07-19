## Summary

Adds a local-first **Adult mode** setting that steers the on-device system prompt so Nova answers legal adult topics more directly, without any cloud moderation.

Stacked on keep-alive + context-budget work (branch cut from `cursor/context-budget-compact-a31e`).

## Changes

- `AdultModePolicy` — prompt suffix (full + compact Android) and prefs key `settings_adult_mode`
- `ModelOrchestrator` loads the pref, appends suffix in `_systemPromptFor` (including compact Gemma 4), clears live chat when the flag changes so the next send picks up the new system prompt
- Settings toggle with confirmation dialog on enable; export/import via settings backup
- Docs in `PLAN-features.md`, `models.md`, `getting-started.md`

## Notes

- Default **off**
- Still refuses illegal / non-consensual / minor-related content in the prompt copy
- Cannot fully override base-model refusals baked into Gemma weights

## Verification

- `flutter analyze` — clean
- `flutter test` — 178/178 passed

## Manual test

1. Settings → enable **Adult mode** → confirm dialog
2. Ask a legal adult topic — should be less prudish
3. Disable → next message after chat refresh should drop the suffix
4. Export/import settings preserves the flag

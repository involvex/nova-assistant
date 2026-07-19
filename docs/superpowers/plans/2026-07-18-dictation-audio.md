# Continuous Dictation / Audio Attach — Plan Stub

> Expand into a full task plan after share-sheet polish.
> **Do not implement yet.**

**Goal:** Longer hands-free dictation into the composer, plus optional audio file attach for later transcription — without auto-sending mid-utterance.

**Likely touch points:**
- `lib/widgets/voice_input.dart` (already accumulates until listen ends)
- `lib/screens/assistant_screen.dart` — `onPartial` / busy guard
- Attachment row next to gallery / file
- Permissions (`RECORD_AUDIO`)

**Acceptance (draft):**
- Hold/toggle listen fills the text field continuously
- Send only on explicit send (or explicit “send on end” setting, default off)
- Optional: attach `.m4a` / `.wav` shown as chip; transcription v1 can be on-device STT of file or “not supported yet” stub
- Must stay stable on POCO F1 (no second heavy model load for STT beyond system engine)

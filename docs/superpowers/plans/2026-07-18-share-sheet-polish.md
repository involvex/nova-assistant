# Share Sheet Polish — Plan Stub

> Expand into a full task plan after conversation branching ships.
> **Do not implement yet.**

**Goal:** Share a single message or whole chat via the system share sheet (no raw `/data/user/0/...` paths).

**Likely touch points:**
- `lib/services/export_service.dart` (`shareText`)
- `lib/services/chat_history_service.dart` (`exportAsText` / `exportConversationAsText`)
- `lib/widgets/chat_bubble.dart` — `Share` action
- `lib/screens/assistant_screen.dart` / history overflow menu

**Acceptance (draft):**
- Bubble → Share sends that message text
- Chat menu → Share conversation sends full export text
- Works on Android; no file-path snackbars for the happy path

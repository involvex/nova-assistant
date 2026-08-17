# Plan: Quick Wins + Image Generation from Chat

> Implementation plan for 11 unimplemented quick-win items and Image Generation from Chat (#19).
> Quick wins are grouped by effort and dependency. Image generation requires a design decision.

---

## Quick Wins — Implementation Status

| # | Feature | Status | Effort |
|---|---------|--------|--------|
| 2 | Message copy with attribution | Done | — |
| 3 | Pull-to-refresh conversation list | Done | — |
| 6 | Screen timeout control | Done | — |
| 10 | Model storage breakdown | Done | — |
| 12 | Regenerate last response | Done | — |
| 1 | Unread message indicator | Not started | Low |
| 4 | Swipe to archive | Partial (delete exists) | Medium |
| 5 | Gesture-based screenshot | Not started | Medium |
| 7 | Vibration feedback | Not started | Low |
| 8 | Haptic feedback toggle | Not started | Low |
| 9 | Animated theme transitions | Not started | Low |
| 11 | Copy code blocks with one tap | Not started | Medium |
| 13 | Quick model switch chip | Partial (app bar exists) | Low |
| 14 | Conversation rename from header tap | Partial (dialog exists) | Low |
| 15 | Share conversation as image | Not started | Medium |

---

## Batch 1: Settings & Preferences (Low Effort, No UI Redesign)

### 1. Haptic Feedback Toggle in Settings
- **Files:** `lib/screens/settings_screen.dart`, `lib/services/user_preferences_service.dart`
- **Add:** `settings_haptic_enabled` boolean preference
- **UI:** Toggle tile in existing settings sections (Performance or Capture & voice)
- **Pattern:** Follow existing `_toggleTile` pattern in settings_screen.dart

### 2. Animated Theme Transitions
- **Files:** `lib/main.dart`
- **Add:** `themeAnimationDuration` and `themeAnimationCurve` to `MaterialApp`
- **Values:** 300ms easeInOut crossfade
- **Pattern:** Minimal change to existing `_buildLightTheme()` / `_buildDarkTheme()`

### 3. Model Storage Breakdown (Add Custom Models)
- **Files:** `lib/screens/settings_screen.dart`
- **Fix:** Current implementation only shows `ModelManager.instance.installedModels`
- **Add:** Include `ModelManager.instance.customModels` in the breakdown
- **Pattern:** Extend existing `_loadStorageBreakdown()` FutureBuilder

---

## Batch 2: Chat UI Polish (Low-Medium Effort)

### 4. Unread Message Indicator
- **Files:** `lib/models/conversation.dart`, `lib/services/chat_history_service.dart`, `lib/screens/assistant_screen.dart`, `lib/screens/chat_history_screen.dart`
- **Model:** Add `int unreadCount` to `Conversation` (default 0)
- **Service:** Add `unreadUpdateStream` broadcast controller to `ChatHistoryService`
- **UI:** Wrap history icon in app bar with `Stack` + `Positioned` badge
- **Logic:** Increment when messages arrive while not viewing that conversation; clear on open
- **Pattern:** Follow existing `StreamController.broadcast()` pattern

### 5. Copy Code Blocks with One Tap
- **Files:** `lib/widgets/chat_bubble.dart`
- **Approach:** Use `flutter_markdown` extension points — inject custom code block builder via `MarkdownBody.builders`
- **UI:** Wrap code blocks in `Stack` with positioned copy button (top-right)
- **Action:** Extract code text, `Clipboard.setData`
- **Pattern:** Follow existing `_BubbleAction` button pattern in ChatBubble

### 6. Quick Model Switch Chip from Chat
- **Files:** `lib/screens/assistant_screen.dart`
- **UI:** Add small chip near input bar or status bar showing current effective model
- **Action:** Tappable to open existing `ModelSelectorSheet`
- **Pattern:** Use existing `SuggestionChip` styling
- **State:** Reuse existing `_selectedModel` / `_selectedCustomModel`

### 7. Conversation Rename from Header Tap
- **Files:** `lib/screens/chat_history_screen.dart`
- **UI:** Add `onTap` / `InkWell` to conversation title in list tile
- **Action:** Call existing `_renameConversation()` dialog
- **Pattern:** Minimal change — wrap title `Text` in gesture detector

---

## Batch 3: Actions & Gestures (Medium Effort)

### 8. Vibration Feedback on Send / Tool Execution
- **Files:** `lib/screens/assistant_screen.dart`, optionally `lib/widgets/chat_bubble.dart`
- **Approach:** Use `HapticFeedback.lightImpact()` on send, `HapticFeedback.mediumImpact()` on tool completion
- **Dependency:** None (Flutter SDK `HapticFeedback`)
- **Pattern:** Fire in `_sendMessage()` and tool result handler
- **Toggle:** Wrap in `settings_haptic_enabled` preference (from Batch 1)

### 9. Gesture-Based Screenshot (Three-Finger Swipe)
- **Files:** `lib/screens/assistant_screen.dart`
- **Approach A (Flutter):** `RawGestureDetector` with `MultiDragGestureRecognizer` tracking 3 pointers + horizontal movement
- **Approach B (Native):** Android `GestureDetector` in `MainActivity.kt`, invoke `ScreenshotService` method channel
- **Recommendation:** Approach B (more reliable on Android, no Flutter gesture conflicts)
- **Pattern:** Reuse existing `ScreenshotService` + `take_screenshot` tool

### 10. Swipe to Archive Conversation
- **Files:** `lib/models/conversation.dart`, `lib/screens/chat_history_screen.dart`, `lib/services/chat_history_service.dart`
- **Model:** Add `bool isArchived` to `Conversation` with `copyWith`
- **UI:** Change existing `Dismissible` to offer Archive (primary) + Delete (secondary)
- **Filter:** Add archived section or filter in chat history
- **Pattern:** Follow existing `Dismissible` + `_deleteConversation` pattern

---

## Batch 4: Sharing (Medium Effort)

### 11. Share Conversation as Image
- **Files:** `lib/screens/assistant_screen.dart`, `lib/services/export_service.dart`, `android/app/src/main/kotlin/.../NovaChannelRegistrar.kt`
- **Approach:** Render conversation bubbles in `RepaintBoundary` → `toImage()` → temp PNG → native share intent
- **Native:** Add `shareImage` method to existing `dev.nova.assistant/share` channel
- **UI:** Add action in conversation popup menu
- **Pattern:** Follow existing `shareText()` pattern in ExportService

---

## Image Generation from Chat (#19 P2)

### Current State
- **Zero image generation capability** exists
- `docs/models.md` explicitly states: "On-device image generation (not in this build)"
- No diffusion models, no image generation APIs, no `generate_image` tool
- Existing image support is **input only** (vision): screenshots, gallery picker, `imageData` on `ChatMessage`

### Design Decision Required

**Question:** How should Nova generate images?

| Option | Description | Pros | Cons | Privacy |
|--------|-------------|------|------|---------|
| **A. On-device diffusion** | LiteRT multi-graph diffusion pipeline (FLUX, SD) | Fully private, on-device | Explicitly out of scope per docs; requires separate native LiteRT GPU pipeline; 500MB-2GB models; Pixel 8a+ class hardware | ✅ Full |
| **B. External API** | Call OpenAI DALL-E / Stability AI via platform channel | High quality, fast | Requires internet + API keys; breaks "no data leaves phone" promise | ❌ None |
| **C. MCP tool delegation** | Expose `generate_image` as MCP tool; user provides backend | Leverages existing MCP infra; user controls backend | Depends on user's MCP setup; not self-contained | ⚠️ Depends on user's MCP server |
| **D. LAN/remote inference** | Route to remote diffusion server on local network | Uses existing remote inference pattern | Requires user to run own server; complex UX | ⚠️ Depends on user's server |

### Recommendation
**Option C (MCP tool delegation)** is the safest first step:
- Aligns with Nova's privacy-first architecture
- Leverages existing `McpService` infrastructure
- Zero new native dependencies
- Users with capable MCP servers get image generation immediately
- Can be extended later with on-device or LAN options

**If the user wants self-contained image generation without MCP, Option D (LAN remote)** is the next best choice, reusing the existing `RemoteInferenceClient` with a `/generate-image` endpoint.

### Implementation (Assuming Option C)

- **Files:** `lib/tools/tool_definitions.dart` (add `generate_image` tool schema), `lib/services/mcp_service.dart` (expose to MCP tools), `lib/screens/assistant_screen.dart` (UI trigger)
- **Tool schema:** `generate_image` with `prompt` (string) and optional `size` parameter
- **Display:** Generated image bytes stored in `ChatMessage.imageData` — display path already exists in `ChatBubble`
- **No new dependencies** if using MCP delegation

### Implementation (Assuming Option D — LAN Remote)

- **Files:** `lib/tools/tool_definitions.dart`, `lib/services/remote_inference_client.dart`, `lib/models/remote_inference_config.dart`
- **Endpoint:** POST `/v1/images/generations` (OpenAI-compatible)
- **Display:** Same `ChatMessage.imageData` path
- **Config:** Add image generation base URL + API key to `RemoteInferenceSettingsScreen`

---

## Open Question

**Which image generation approach should be implemented?**

- **Recommended:** MCP tool delegation (Option C) — lowest risk, leverages existing MCP infrastructure, preserves privacy promise
- **Alternative:** LAN remote inference (Option D) — self-contained for users with compatible local servers
- **Not recommended:** On-device (A) or external API (B) due to architectural and privacy constraints

---

## Validation Plan

For each batch:
1. Run `flutter analyze` — no new errors
2. Run `dart format .` — consistent formatting
3. Run `flutter test` — existing tests pass
4. Manual UI verification on Android emulator/device

For image generation:
1. Verify `generate_image` tool appears in available tools list
2. Test with a mock MCP server (Option C) or mock remote endpoint (Option D)
3. Verify generated image renders inline in ChatBubble
4. Verify image is not persisted to SharedPreferences (follows existing image stripping pattern)

---

## Rollout Order

1. Batch 1 (Settings) — 3 items, ~1-2 hours
2. Batch 2 (Chat UI) — 4 items, ~2-3 hours
3. Batch 3 (Actions) — 3 items, ~2-3 hours
4. Batch 4 (Sharing) — 1 item, ~1-2 hours
5. Image generation — depends on approach decision, ~2-4 hours

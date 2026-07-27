# Nova Assistant — Feature Suggestions

> Suggested features for future implementation. Organized by category and priority.
> Each suggestion includes a brief description, implementation approach, and relevant files.

---

## P0 — High Impact, Low Effort

### 1. Dark / Light Theme Toggle

**Why:** The app is currently hardcoded to a dark theme (`Color(0xFF0D0D1A)`). A light theme improves readability in bright environments and accessibility.

**Approach:**
- Add `settings_theme_mode` to SharedPreferences (`light`, `dark`, `system`)
- Wrap the top-level `MaterialApp` with a `ThemeData` that switches
- Use `platformBrightness` to detect system theme when set to `system`
- Add a theme toggle in Settings screen

**Files to modify:** `lib/main.dart`, `lib/screens/settings_screen.dart`, `lib/services/user_preferences_service.dart`

---

### 2. Font Size / Display Size Setting

**Why:** Some users struggle with small text in chat bubbles. A font size preference improves accessibility.

**Approach:**
- Add `settings_font_scale` to SharedPreferences (small / medium / large / extra-large)
- Apply `MediaQuery.textScaleFactor` override in the chat list
- Add slider or segmented control in Settings

**Files to modify:** `lib/screens/assistant_screen.dart`, `lib/screens/settings_screen.dart`

---

### 3. Pin Important Chat Messages

**Why:** Users often want to flag key messages for quick reference without saving the whole conversation.

**Approach:**
- Add `isPinned` field to `ChatMessage` model
- Add a pin button on message long-press context menu
- Create a "Pinned Messages" section in the chat or a dedicated screen
- Persist pin state in the conversation JSON

**Files to modify:** `lib/models/chat_message.dart`, `lib/widgets/chat_bubble.dart`, `lib/screens/assistant_screen.dart`, `lib/services/chat_history_service.dart`

---

### 4. Markdown Export for Individual Conversations

**Why:** The app exports as plain text and JSON, but not as Markdown (`.md`) — which is the native format for a Markdown rendering assistant.

**Approach:**
- Add `exportConversationAsMarkdown()` to `ChatHistoryService`
- Format user/assistant turns with Markdown headings and code blocks
- Add "Export as Markdown" option in the conversation menu

**Files to modify:** `lib/services/chat_history_service.dart`, `lib/screens/assistant_screen.dart`

---

### 5. Conversation Fork (Duplicate + Edit)

**Why:** Users sometimes want to explore a different direction from a specific point in a conversation without starting from scratch.

**Approach:**
- Add a "Fork from here" option in message long-press menu
- Truncate conversation at selected message index
- Create a new conversation with that prefix
- Allow normal editing and continued generation on the fork

**Files to modify:** `lib/screens/assistant_screen.dart`, `lib/services/chat_history_service.dart`, `lib/models/conversation.dart`

---

## P1 — Medium Impact, Moderate Effort

### 6. In-Chat Code Execution / Sandbox

**Why:** Nova already has code-related tools but no sandboxed execution environment for running short scripts or evaluating code snippets directly in chat.

**Approach:**
- Add a `run_code` tool that accepts a language and code string
- Execute in a safe Dart VM isolate or shell subprocess (Android only)
- Return stdout/stderr / exit code as tool result
- Add a "code execution" capability badge to the model card

**Files to modify:** `lib/tools/tool_definitions.dart`, `lib/services/task_service.dart` or new `lib/services/code_executor_service.dart`, `lib/screens/settings_screen.dart`

---

### 7. Calendar & Event Creation Tools

**Why:** The app has alarm tools but no general calendar integration. Users would benefit from creating events or checking their schedule.

**Approach:**
- Add `create_event` and `list_events` tools in `tool_definitions.dart`
- Use Android `CalendarContract` via platform channel to read/write events
- Add reminder/notification scheduling integration

**Files to modify:** `lib/tools/tool_definitions.dart`, `android/app/src/main/kotlin/dev/nova/assistant/MainActivity.kt`, `lib/platform/tool_executor_service.dart`

---

### 8. Clipboard-Aware Context Injection

**Why:** Users often copy text and want Nova to analyze, summarize, or respond to it without manually pasting it into the chat.

**Approach:**
- On long-press of the input bar, offer "Paste & Send" or "Analyze clipboard"
- Read clipboard content via `Clipboard.getData(Clipboard.kTextPlain)`
- Optionally auto-send if user has a "paste-and-go" preference

**Files to modify:** `lib/screens/assistant_screen.dart`

---

### 9. Conversation Templates / Presets

**Why:** New users may not know what to ask. Pre-built conversation templates (e.g., "Summarize this article", "Help me plan a trip", "Debug this code") lower the barrier to entry.

**Approach:**
- Add a `prompt_presets` category for "Conversation Starters" (distinct from existing prompt presets which are system prompts)
- Show a template carousel or grid on the empty state screen
- Each template pre-fills the input bar with a ready-to-send prompt

**Files to modify:** `lib/screens/assistant_screen.dart`, `lib/models/prompt_preset.dart`, `lib/services/prompt_presets_service.dart`

---

### 10. Message Search Within Conversation

**Why:** The app has a conversation search screen (`conversation_search_screen.dart`) but no in-chat search for quick lookup within the current thread.

**Approach:**
- Add a search bar overlay in the chat message list
- Filter messages by text content in real time
- Highlight matching text within each bubble
- Show match count and navigation (next/previous)

**Files to modify:** `lib/screens/assistant_screen.dart`, `lib/widgets/chat_bubble.dart`

---

### 11. Battery-Aware Model Degradation

**Why:** The app already has idle unload and RAM gate, but no battery-level awareness. On low battery, the model could auto-switch to a lighter model or disable heavy features.

**Approach:**
- Monitor battery level via `BatteryManager` on Android / ` UIDevice` on iOS
- When battery < 20% and model is Gemma 4 E2B, prompt or auto-switch to Gemma 3 1B or SmolLM
- Add a battery indicator in the status bar or model picker

**Files to modify:** `lib/screens/assistant_screen.dart`, `lib/services/platform_adaptation_service.dart`, `lib/services/model_orchestrator.dart`

---

### 12. Chat Wallpaper / Bubble Theme

**Why:** Personalization increases engagement. A subtle background pattern or custom bubble color scheme would differentiate Nova from other chat apps.

**Approach:**
- Add `settings_bubble_theme` preference (default, ocean, forest, neon)
- Apply color overrides to `ChatBubble` and `AssistantScreen` background
- Keep default theme as the safe option

**Files to modify:** `lib/screens/assistant_screen.dart`, `lib/widgets/chat_bubble.dart`, `lib/screens/settings_screen.dart`

---

## P2 — Medium Impact, Higher Effort

### 13. Multi-Conversation Split View (Tablet / Desktop)

**Why:** On larger screens, users can benefit from seeing the conversation list alongside the chat, similar to Slack or email clients.

**Approach:**
- Detect screen width with `LayoutBuilder` or `MediaQuery`
- On wide screens (>600dp), show a side panel of conversation list + chat
- Implement with `Row` + `Expanded` layout
- Add a "New conversation" button in the side panel

**Files to modify:** `lib/screens/assistant_screen.dart`, navigation/routing setup

---

### 14. Keyboard Shortcuts (Desktop Platforms)

**Why:** On Windows/Linux desktop, keyboard shortcuts significantly improve productivity for power users.

**Approach:**
- Use `RawKeyboardListener` or `KeyboardListener` widget
- Map Ctrl+Enter to send, Ctrl+Shift+M to toggle model picker, Ctrl+K for command palette, Ctrl+F for search
- Show shortcut hints in tooltips

**Files to modify:** `lib/screens/assistant_screen.dart`

---

### 15. Command Palette

**Why:** A quick-access command palette (Ctrl+K / Cmd+K) lets users jump to actions without navigating menus — common in modern apps.

**Approach:**
- Build a searchable action menu overlay
- Include: "New chat", "Settings", "Model picker", "Export", "Compact context", "Clear history", "Toggle thinking mode"
- Filter actions by typed query

**Files to modify:** `lib/screens/assistant_screen.dart` or new `lib/screens/command_palette_screen.dart`

---

### 16. Structured Data in Chat (Tables, Checklists)

**Why:** Nova renders Markdown but has limited support for interactive tables or checkbox lists. Rendering these natively would improve readability of task-oriented responses.

**Approach:**
- Enhance the Markdown renderer with custom `table` and `task_list` widget builders
- Render tables as Flutter `DataTable` widgets
- Render task lists as interactive checkboxes that toggle on tap

**Files to modify:** `lib/widgets/chat_bubble.dart` (MarkdownBody builder), or a custom Markdown widget wrapper

---

### 17. Image Generation from Chat

**Why:** Some on-device models can generate images from text. If a compatible model is available, Nova could offer image generation as a tool.

**Approach:**
- Add a `generate_image` tool that routes to a suitable model or external API
- Display generated images inline as attachment data
- Store generated images in the chat message `imageData` field

**Files to modify:** `lib/tools/tool_definitions.dart`, `lib/screens/assistant_screen.dart`

---

### 18. Offline Capability Indicator & Smart Download

**Why:** The offline banner exists but is passive. An intelligent system could queue model downloads when on WiFi and warn before downloading on cellular.

**Approach:**
- Add a `ConnectivityWatcher` service using `connectivity_plus` package
- Prefer WiFi for model downloads; show confirmation dialog on cellular
- Show download queue status in Settings
- Auto-download recommended models on first launch when on WiFi

**Files to modify:** New `lib/services/connectivity_service.dart`, `lib/screens/model_browser_screen.dart`, `lib/screens/settings_screen.dart`

---

### 19. Response Confidence / Source Attribution

**Why:** Users may want to know how confident the model is in its answer, especially for factual queries. Source attribution helps verify information.

**Approach:**
- Add a confidence indicator (e.g., a small icon or badge) on assistant messages
- For web search results, show cited URLs or source domains
- Implement as an optional overlay or expandable section on each bubble

**Files to modify:** `lib/widgets/chat_bubble.dart`, `lib/services/tool_executor_service.dart`

---

### 20. Learning Mode (Spaced Repetition Drill)

**Why:** The app has a "student" assistant role but no structured learning/practice mode. A flashcard or quiz mode would make Nova a genuinely useful study tool.

**Approach:**
- Add a "Learning Mode" toggle in Settings or a dedicated study screen
- Generate flashcards from conversation content
- Implement spaced repetition algorithm (e.g., SM-2)
- Track retention metrics and show progress

**Files to modify:** New `lib/screens/learning_mode_screen.dart`, `lib/services/learning_service.dart`, `lib/models/flashcard.dart`

---

## P3 — Lower Impact, Complex Implementation

### 21. Plugin System / Extension Points

**Why:** A plugin system would let third parties add custom tools, models, or UI extensions without modifying the core app.

**Approach:**
- Define a plugin manifest format (JSON) with tool definitions, model configs, and UI entry points
- Load plugins from a `plugins/` directory in app documents
- Sandbox plugin execution to prevent crashes

**Files to modify:** New `lib/services/plugin_manager.dart`, `lib/models/plugin.dart`, architecture docs

---

### 22. Encrypted Cloud Sync (Optional)

**Why:** Currently data stays local. An opt-in encrypted sync would allow users to back up conversations and settings across devices.

**Approach:**
- Use `encrypt` package for AES-256 encryption of sync payloads
- Support cloud providers (Google Drive, iCloud, WebDAV)
- Add sync settings in Settings screen with encryption key management

**Files to modify:** New `lib/services/sync_service.dart`, `lib/screens/settings_screen.dart`

---

### 23. Real-Time Translation

**Why:** The assistant has a language awareness setting but no real-time translation. Users could chat in one language and get responses in another.

**Approach:**
- Add `target_language` setting per conversation
- On send, include language preference in system prompt
- For model output, apply translation if target differs from input language
- Alternatively, use a translation tool via platform channel

**Files to modify:** `lib/models/assistant_language.dart`, `lib/services/model_orchestrator.dart`, `lib/screens/assistant_screen.dart`

---

### 24. Multi-User / Family Profiles

**Why:** On shared devices, different family members might want separate conversations, identity settings, and tool preferences.

**Approach:**
- Add profile management (create, switch, delete profiles)
- Each profile has its own conversation history, identity config, and preferences
- Lock profile switch with PIN or biometrics

**Files to modify:** New `lib/services/profile_service.dart`, `lib/models/user_profile.dart`, `lib/screens/settings_screen.dart`

---

### 25. Voice-Controlled Navigation

**Why:** The app has voice input for chat but not voice commands for navigation (e.g., "go to settings", "new chat", "stop").

**Approach:**
- Add a voice command service that runs a small keyword recognition model
- Map recognized commands to navigation actions
- Add a voice control toggle in Settings

**Files to modify:** New `lib/services/voice_command_service.dart`, `lib/screens/settings_screen.dart`

---

### 26. Custom CSS/Theme Builder

**Why:** Power users and accessibility users may want fine-grained control over the visual appearance beyond just light/dark mode.

**Approach:**
- Create a theme editor with color pickers for: background, bubble user/bubble assistant, text, accents, status bar
- Persist custom theme as JSON in SharedPreferences
- Export/import themes as shareable JSON files

**Files to modify:** New `lib/services/theme_editor_service.dart`, `lib/screens/settings_screen.dart`

---

### 27. Automated Backup with Scheduling

**Why:** Settings backup exists but is manual. An automated backup scheduler would ensure users don't lose data.

**Approach:**
- Add `settings_backup_schedule` preference (daily, weekly, monthly, manual)
- Automatically trigger backup at the scheduled time using `flutter_local_notifications`
- Keep last N backups automatically (rotate old ones)

**Files to modify:** `lib/services/settings_backup_service.dart`, `lib/screens/settings_screen.dart`

---

### 28. Model Benchmarking / Comparison Tool

**Why:** Users with multiple models installed may want to compare model quality, speed, and resource usage for the same query.

**Approach:**
- Add a "Benchmark" mode that sends the same query to multiple models in parallel
- Display response quality metrics (words/second, tokens/second, memory usage)
- Show a comparison table or card view

**Files to modify:** New `lib/screens/model_benchmark_screen.dart`, `lib/services/model_orchestrator.dart`

---

### 29. Context Window Visualization

**Why:** The high-context toggle exists but users can't see how much of their context window is used. A visual indicator would help them understand when compaction is needed.

**Approach:**
- Add a context usage bar (like a progress bar) above the message list
- Show tokens used vs. model limit
- Color-code: green (healthy), yellow (approaching limit), red (over limit)
- Tap to open compaction dialog

**Files to modify:** `lib/screens/assistant_screen.dart`, `lib/services/message_limits.dart`

---

### 30. Smart Reply Suggestions (Quick Actions)

**Why:** The follow-up suggestion system exists but could be smarter — offering contextual quick actions like "Translate this", "Make this a task", "Email this to...".

**Approach:**
- Enhance `FollowUpSuggestionService` to detect intent patterns (e.g., "translate", "task", "email")
- Show action chips that perform the operation directly rather than just sending a follow-up query
- Add a "Quick Actions" section below the input bar

**Files to modify:** `lib/services/follow_up_suggestion_service.dart`, `lib/screens/assistant_screen.dart`

---

## Quick Wins (Low Effort)

These are small, high-value additions that can be implemented quickly:

| # | Feature | Effort | Impact |
|---|---------|--------|--------|
| 31 | **Unread message indicator** — badge on chat history icon when new messages arrive | Low | Medium |
| 32 | **Message copy with attribution** — copy includes model name and timestamp | Low | Low |
| 33 | **Pull-to-refresh conversation list** | Low | Low |
| 34 | **Swipe to archive/conversation** | Medium | Medium |
| 35 | **Gesture-based screenshot** — three-finger swipe to capture screen | Medium | Medium |
| 36 | **Screen timeout control** — keep screen on during streaming | Low | Medium |
| 37 | **Vibration feedback** on send / tool execution | Low | Low |
| 38 | **Haptic feedback** toggle in settings | Low | Low |
| 39 | **Animated theme transitions** | Low | Low |
| 40 | **Model storage breakdown** in settings (MB per model) | Low | Medium |

---

## Notes for Implementers

### Architecture Guidelines (from AGENTS.md)

- **Singleton pattern** for services: `class MyService { static MyService? _instance; static MyService get instance => _instance ??= MyService._(); MyService._(); }`
- **Stream-based communication**: Use `StreamController<String>.broadcast()` for status updates
- **Platform channels** for native functionality: `static const _channel = MethodChannel('dev.nova.assistant/tools');`
- **Always close streams** in `dispose()`
- **Check `mounted`** before `setState` in async callbacks
- **Use `withValues()`** instead of `withOpacity()` for colors
- **Trailing commas** on multi-line parameters (enforced by `analysis_options.yaml`)

### Testing Guidelines

- Mirror `lib/` structure in `test/`
- Use `mockito` for mocking dependencies
- Run `flutter test` before committing
- Run `flutter analyze` and `dart format .` before committing

### PR Checklist

- [ ] `flutter analyze` — no errors
- [ ] `dart format .` — consistent formatting
- [ ] `flutter test` — all tests pass
- [ ] No debug prints in production code
- [ ] No hardcoded strings (use constants)
- [ ] Trailing commas on multi-line parameters
- [ ] Update this file if a new suggestion is implemented

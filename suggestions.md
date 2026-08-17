# Nova Assistant — Feature Suggestions

> Suggested features for future implementation. Organized by category and priority.
> Each suggestion includes a brief description, implementation approach, and relevant files.

---

## P0 — High Impact, Low Effort

### All P0 Items Implemented

| # | Feature | Status | Implementation |
|---|---------|--------|----------------|
| 1 | Dark/Light Theme Toggle | Done | ThemeModeSetting in main.dart, settings UI |
| 2 | Font Size / Display Size | Done | fontScale in UserPreferencesService |
| 3 | Pin Important Messages | Done | isPinned on ChatMessage, pin/unpin in context menu |
| 4 | Markdown Export | Done | exportConversationAsMarkdown in ChatHistoryService |
| 5 | Conversation Fork | Done | forkConversation in ChatHistoryService |

---

## P1 — Medium Impact, Moderate Effort

### 6. In-Chat Code Execution / Sandbox

**Why:** Nova already has code-related tools but no sandboxed execution environment for running short scripts or evaluating code snippets directly in chat.

**Approach:**
- Add a `run_code` tool that accepts a language and code string
- Execute in a safe Dart VM isolate or shell subprocess (Android only)
- Return stdout/stderr / exit code as tool result
- Add a code execution capability badge to the model card

**Files to modify:** lib/tools/tool_definitions.dart, lib/services/task_service.dart or new lib/services/code_executor_service.dart, lib/screens/settings_screen.dart

---

### 7. Calendar & Event Creation Tools

**Why:** The app has alarm tools but no general calendar integration. Users would benefit from creating events or checking their schedule.

**Approach:**
- Add `create_event` and `list_events` tools in tool_definitions.dart
- Use Android CalendarContract via platform channel to read/write events
- Add reminder/notification scheduling integration

**Files to modify:** lib/tools/tool_definitions.dart, android/app/src/main/kotlin/dev/nova/assistant/MainActivity.kt, lib/platform/tool_executor_service.dart

---

### 8. Clipboard-Aware Context Injection

**Why:** Users often copy text and want Nova to analyze, summarize, or respond to it without manually pasting it into the chat.

**Approach:**
- On long-press of the input bar, offer Paste & Send or Analyze clipboard
- Read clipboard content via Clipboard.getData(Clipboard.kTextPlain)
- Optionally auto-send if user has a paste-and-go preference
- Add clipboard content preview in the input bar

**Files to modify:** lib/screens/assistant_screen.dart

**Status:** Implemented

---

### 9. Conversation Templates / Presets (Empty-State Carousel)

**Why:** New users may not know what to ask. Pre-built conversation templates on the empty state screen lower the barrier to entry.

**Approach:**
- Add a template carousel or grid on the empty state screen
- Each template pre-fills the input bar with a ready-to-send prompt
- Include categories: Summarize, Plan, Debug, Learn, Create
- Show only when conversation is empty

**Files to modify:** lib/screens/assistant_screen.dart, lib/models/prompt_preset.dart, lib/services/prompt_presets_service.dart

**Status:** Implemented

---

### 10. In-Chat Message Search

**Why:** The app has inter-conversation search (conversation_search_screen.dart) but no in-chat search for quick lookup within the current thread.

**Approach:**
- Add a search bar overlay in the chat message list
- Filter messages by text content in real time
- Highlight matching text within each bubble
- Show match count and navigation (next/previous)

**Files to modify:** lib/screens/assistant_screen.dart, lib/widgets/chat_bubble.dart

**Status:** Implemented

---

### 11. Battery-Aware Model Switching

**Why:** The app has idle-release battery optimization, but no battery-level awareness. On low battery, the model could auto-switch to a lighter model or disable heavy features.

**Approach:**
- Monitor battery level via BatteryManager on Android
- When battery < 20% and model is Gemma 4 E2B, prompt or auto-switch to Gemma 3 1B or SmolLM
- Add a battery indicator in the status bar or model picker
- Respect user preference (auto vs manual)

**Files to modify:** lib/screens/assistant_screen.dart, lib/services/platform_adaptation_service.dart, lib/services/model_orchestrator.dart

**Status:** Implemented

---

### 12. Chat Wallpaper / Bubble Theme

**Why:** Personalization increases engagement. A subtle background pattern or custom bubble color scheme would differentiate Nova from other chat apps.

**Approach:**
- Add settings_bubble_theme preference (default, ocean, forest, neon, custom)
- Apply color overrides to ChatBubble and AssistantScreen background
- Keep default theme as the safe option
- Allow custom colors via color picker

**Files to modify:** lib/screens/assistant_screen.dart, lib/widgets/chat_bubble.dart, lib/screens/settings_screen.dart

**Status:** Implemented

---

### 13. Knowledge Base RAG (Document-Based Memory)

**Why:** The app has general memory but no structured knowledge base for ingesting and querying documents. Users want to chat with their own files.

**Approach:**
- Add a knowledge_base service that ingests PDFs, text, markdown files
- Chunk and embed documents for semantic retrieval
- Surface KB context automatically in the system prompt when relevant
- Add a KnowledgeBaseScreen to manage documents

**Files to modify:** New lib/services/knowledge_base_service.dart, lib/screens/knowledge_base_screen.dart, lib/models/knowledge_base.dart

---

### 14. Inference Backend Selection UI

**Why:** The app supports LiteRT, MediaPipe, and Remote backends, but there is no user-facing toggle to switch between them or see which is active.

**Approach:**
- Add a backend selector in Settings or the model picker sheet
- Persist selection in UserPreferences
- Show active backend status in the model card
- Handle backend-specific capability warnings (e.g., vision not supported on web LiteRT)

**Files to modify:** lib/models/inference_backend.dart, lib/screens/settings_screen.dart, lib/screens/model_selector_sheet.dart

---

## P2 — Medium Impact, Higher Effort

### 15. Multi-Conversation Split View (Tablet / Desktop)

**Why:** On larger screens, users can benefit from seeing the conversation list alongside the chat, similar to Slack or email clients.

**Approach:**
- Detect screen width with LayoutBuilder or MediaQuery
- On wide screens (>600dp), show a side panel of conversation list + chat
- Implement with Row + Expanded layout
- Add a New conversation button in the side panel

**Files to modify:** lib/screens/assistant_screen.dart, navigation/routing setup

---

### 16. Keyboard Shortcuts (Desktop Platforms)

**Why:** On Windows/Linux desktop, keyboard shortcuts significantly improve productivity for power users.

**Approach:**
- Use RawKeyboardListener or KeyboardListener widget
- Map Ctrl+Enter to send, Ctrl+Shift+M to toggle model picker, Ctrl+K for command palette, Ctrl+F for search
- Show shortcut hints in tooltips

**Files to modify:** lib/screens/assistant_screen.dart

---

### 17. Command Palette

**Why:** A quick-access command palette (Ctrl+K / Cmd+K) lets users jump to actions without navigating menus — common in modern apps.

**Approach:**
- Build a searchable action menu overlay
- Include: New chat, Settings, Model picker, Export, Compact context, Clear history, Toggle thinking mode
- Filter actions by typed query

**Files to modify:** lib/screens/assistant_screen.dart or new lib/screens/command_palette_screen.dart

---

### 18. Structured Data in Chat (Tables, Checklists)

**Why:** Nova renders Markdown but has limited support for interactive tables or checkbox lists. Rendering these natively would improve readability of task-oriented responses.

**Approach:**
- Enhance the Markdown renderer with custom table and task_list widget builders
- Render tables as Flutter DataTable widgets
- Render task lists as interactive checkboxes that toggle on tap
- Persist checkbox state to the task service

**Files to modify:** lib/widgets/chat_bubble.dart (MarkdownBody builder), or a custom Markdown widget wrapper

---

### 19. Image Generation from Chat

**Why:** Some on-device models can generate images from text. If a compatible model is available, Nova could offer image generation as a tool.

**Approach:**
- Add a generate_image tool that routes to a suitable model or external API
- Display generated images inline as attachment data
- Store generated images in the chat message imageData field

**Files to modify:** lib/tools/tool_definitions.dart, lib/screens/assistant_screen.dart

---

### 20. Offline Capability Indicator & Smart Download

**Why:** The offline banner exists but is passive. An intelligent system could queue model downloads when on WiFi and warn before downloading on cellular.

**Approach:**
- Add a ConnectivityWatcher service using connectivity_plus package
- Prefer WiFi for model downloads; show confirmation dialog on cellular
- Show download queue status in Settings
- Auto-download recommended models on first launch when on WiFi

**Files to modify:** New lib/services/connectivity_service.dart, lib/screens/model_browser_screen.dart, lib/screens/settings_screen.dart

**Status:** Partial — DownloadNetworkGate exists (WiFi-only + cellular confirm), but no download queue UI or first-launch auto-download.

---

### 21. Response Confidence / Source Attribution

**Why:** Users may want to know how confident the model is in its answer, especially for factual queries. Source attribution helps verify information.

**Approach:**
- Add a confidence indicator (e.g., a small icon or badge) on assistant messages
- For web search results, show cited URLs or source domains
- Implement as an optional overlay or expandable section on each bubble

**Files to modify:** lib/widgets/chat_bubble.dart, lib/services/tool_executor_service.dart

---

### 22. Learning Mode (Spaced Repetition Drill)

**Why:** The app has a student assistant role but no structured learning/practice mode. A flashcard or quiz mode would make Nova a genuinely useful study tool.

**Approach:**
- Add a Learning Mode toggle in Settings or a dedicated study screen
- Generate flashcards from conversation content
- Implement spaced repetition algorithm (e.g., SM-2)
- Track retention metrics and show progress

**Files to modify:** New lib/screens/learning_mode_screen.dart, lib/services/learning_service.dart, lib/models/flashcard.dart

---

### 23. Context Window Usage Visualization

**Why:** The high-context toggle exists but users can't see how much of their context window is used. A visual indicator would help them understand when compaction is needed.

**Approach:**
- Add a context usage bar (like a progress bar) above the message list
- Show tokens used vs. model limit
- Color-code: green (healthy), yellow (approaching limit), red (over limit)
- Tap to open compaction dialog

**Files to modify:** lib/screens/assistant_screen.dart, lib/utils/message_limits.dart

---

### 24. Model Benchmarking / Comparison Tool

**Why:** Users with multiple models installed may want to compare model quality, speed, and resource usage for the same query.

**Approach:**
- Add a Benchmark mode that sends the same query to multiple models in parallel
- Display response quality metrics (words/second, tokens/second, memory usage)
- Show a comparison table or card view

**Files to modify:** New lib/screens/model_benchmark_screen.dart, lib/services/model_orchestrator.dart

---

### 25. Smart Quick Actions

**Why:** The follow-up suggestion system exists but could be smarter — offering contextual quick actions like Translate this, Make this a task, Email this to... that perform the operation directly.

**Approach:**
- Enhance FollowUpSuggestionService to detect intent patterns (e.g., translate, task, email)
- Show action chips that perform the operation directly rather than just sending a follow-up query
- Add a Quick Actions section below the input bar

**Files to modify:** lib/services/follow_up_suggestion_service.dart, lib/screens/assistant_screen.dart

**Status:** Partial — FollowUpSuggestionService generates text follow-ups, but no action chips that execute operations directly.

---

### 26. Overlay Chat / Floating Chat

**Why:** On Android, users may want a floating chat window that overlays other apps for quick access to Nova without leaving their current task.

**Approach:**
- Use Android system overlay permission (SYSTEM_ALERT_WINDOW)
- Render a minimal chat bubble that expands to full chat UI
- Implement via overlay_service.dart and new overlay_chat_screen.dart
- Add toggle in Settings

**Files to modify:** New lib/services/overlay_service.dart, lib/screens/overlay_chat_screen.dart, android/app/src/main/kotlin/.../OverlayService.kt

**Status:** Implemented

---

### 27. Onboarding Flow & Beginner Mode

**Why:** First-time users need guidance on app capabilities. A guided onboarding and a simplified beginner UI lower the barrier to entry.

**Approach:**
- Add an onboarding screen with capability overview and quick-start tips
- Offer a Beginner Mode with simplified UI (assistant_screen_beginner.dart)
- Allow toggling between beginner and advanced modes

**Files to modify:** New lib/screens/onboarding_screen.dart, lib/screens/assistant_screen_beginner.dart

**Status:** Implemented

---

### 28. Home Widget Integration

**Why:** Users want quick access to Nova from their home screen without opening the full app.

**Approach:**
- Create an Android home screen widget using home_widget package
- Display recent tasks, notes, or quick prompt buttons
- Support widget tap-to-open with pre-filled prompt

**Files to modify:** New lib/services/widget_service.dart, widget layout XML in android/

---

### 29. Export Service (Multi-Format)

**Why:** The app has Markdown export but users may want other formats (JSON, plain text, shareable images).

**Approach:**
- Add an ExportService that supports text, Markdown, and JSON formats
- Include conversation metadata, timestamps, and model names
- Add share intent integration for easy sharing

**Files to modify:** New lib/services/export_service.dart, lib/screens/assistant_screen.dart

**Status:** Implemented

---

### 30. Text-to-Speech (TTS) for Assistant Responses

**Why:** The app has voice input but no voice output. Reading assistant responses aloud improves accessibility and hands-free use.

**Approach:**
- Add a TtsService using flutter_tts or platform TTS
- Add a speaker button on each assistant message
- Support language selection and playback speed

**Files to modify:** New lib/services/tts_service.dart, lib/widgets/chat_bubble.dart

**Status:** Implemented

---

## P3 — Lower Impact, Complex Implementation

### 31. Plugin System / Extension Points

**Why:** A plugin system would let third parties add custom tools, models, or UI extensions without modifying the core app.

**Approach:**
- Define a plugin manifest format (JSON) with tool definitions, model configs, and UI entry points
- Load plugins from a plugins/ directory in app documents
- Sandbox plugin execution to prevent crashes

**Files to modify:** New lib/services/plugin_manager.dart, lib/models/plugin.dart, architecture docs

---

### 32. Encrypted Cloud Sync (Optional)

**Why:** Currently data stays local. An opt-in encrypted sync would allow users to back up conversations and settings across devices.

**Approach:**
- Use encrypt package for AES-256 encryption of sync payloads
- Support cloud providers (Google Drive, iCloud, WebDAV)
- Add sync settings in Settings screen with encryption key management

**Files to modify:** New lib/services/sync_service.dart, lib/screens/settings_screen.dart

---

### 33. Real-Time Translation

**Why:** The assistant has a language awareness setting but no real-time translation. Users could chat in one language and get responses in another.

**Approach:**
- Add target_language setting per conversation
- On send, include language preference in system prompt
- For model output, apply translation if target differs from input language
- Alternatively, use a translation tool via platform channel

**Files to modify:** lib/models/assistant_language.dart, lib/services/model_orchestrator.dart, lib/screens/assistant_screen.dart

---

### 34. Multi-User / Family Profiles

**Why:** On shared devices, different family members might want separate conversations, identity settings, and tool preferences.

**Approach:**
- Add profile management (create, switch, delete profiles)
- Each profile has its own conversation history, identity config, and preferences
- Lock profile switch with PIN or biometrics

**Files to modify:** New lib/services/profile_service.dart, lib/models/user_profile.dart, lib/screens/settings_screen.dart

---

### 35. Voice-Controlled Navigation

**Why:** The app has voice input for chat but not voice commands for navigation (e.g., go to settings, new chat, stop).

**Approach:**
- Add a voice command service that runs a small keyword recognition model
- Map recognized commands to navigation actions
- Add a voice control toggle in Settings

**Files to modify:** New lib/services/voice_command_service.dart, lib/screens/settings_screen.dart

---

### 36. Custom CSS/Theme Builder

**Why:** Power users and accessibility users may want fine-grained control over the visual appearance beyond just light/dark mode.

**Approach:**
- Create a theme editor with color pickers for: background, bubble user/bubble assistant, text, accents, status bar
- Persist custom theme as JSON in SharedPreferences
- Export/import themes as shareable JSON files

**Files to modify:** New lib/services/theme_editor_service.dart, lib/screens/settings_screen.dart

---

### 37. Automated Backup with Scheduling

**Why:** Settings backup exists but is manual. An automated backup scheduler would ensure users don't lose data.

**Approach:**
- Add settings_backup_schedule preference (daily, weekly, monthly, manual)
- Automatically trigger backup at the scheduled time using flutter_local_notifications
- Keep last N backups automatically (rotate old ones)

**Files to modify:** lib/services/settings_backup_service.dart, lib/screens/settings_screen.dart

---

## Quick Wins (Low Effort)

These are small, high-value additions that can be implemented quickly:

| # | Feature | Effort | Impact | Status |
|---|---------|--------|--------|--------|
| 38 | Unread message indicator — badge on chat history icon when new messages arrive | Low | Medium | Open |
| 39 | Message copy with attribution — copy includes model name and timestamp | Low | Low | Open |
| 40 | Pull-to-refresh conversation list | Low | Low | Open |
| 41 | Swipe to archive/conversation | Medium | Medium | Open |
| 42 | Gesture-based screenshot — three-finger swipe to capture screen | Medium | Medium | Open |
| 43 | Screen timeout control — keep screen on during streaming | Low | Medium | Open |
| 44 | Vibration feedback on send / tool execution | Low | Low | Open |
| 45 | Haptic feedback toggle in settings | Low | Low | Open |
| 46 | Animated theme transitions | Low | Low | Open |
| 47 | Model storage breakdown in settings (MB per model) | Low | Medium | Open |
| 48 | Copy code blocks with one tap — dedicated copy button on code blocks | Low | Medium | Open |
| 49 | Regenerate last response — retry the last assistant message | Low | Medium | Open |
| 50 | Quick model switch from chat — chip to swap model mid-conversation | Low | Medium | Open |
| 51 | Conversation rename from header — tap title to rename in-place | Low | Low | Open |
| 52 | Share conversation as image — render chat as shareable image | Low | Low | Open |

---

## Recently Implemented (Not Previously in Suggestions)

These features were implemented but were not in the original suggestions list:

| Feature | Description |
|---------|-------------|
| Remote Inference | OpenAI-compatible LAN client for using remote models |
| Share Intent | Android share sheet integration to open chat from other apps |
| Adult Mode | Optional adult content mode with confirmation dialog |
| Task Management | Create, list, complete to-dos via AI tools |
| Note Management | Create, search, list notes via AI tools |
| Shizuku/Root Tools | Force-stop apps, app info, battery settings (power users) |
| Custom Prompt Presets | Full CRUD for user-defined system prompts |
| Session History Reinject | Reinject chat context on send for continuity |
| High-Context Auto-Compact | Automatic context compaction for long conversations |
| Keep-Warm Policy | Prevent idle model unload when conversation is active |
| Model Release Policy | Battery/RAM-aware model release logic |
| Memory Diagnostics | Diagnostic service for memory system health |
| Settings Backup | Export/import settings as JSON |
| Inference Backend Selection | Toggle between LiteRT, MediaPipe, and Remote backends |
| Model Capability Badges | Visual badges showing model capabilities |
| Knowledge Base RAG | Document ingestion and semantic retrieval for user files |
| Semantic Memory Search | TF-IDF based search for memory and knowledge base |
| MCP Protocol Support | Model Context Protocol with presets and OAuth |
| Overlay Chat | Floating overlay mode for quick access |
| Onboarding & Beginner Mode | Guided onboarding and simplified UI variant |
| Custom Model Import | Import .litertlm and GGUF models |
| Home Widget | Android home screen widget with stats and quick prompts |
| TTS / Text-to-Speech | Read assistant responses aloud |
| Audio Recording | Audio capture tools for voice input |
| Parallel Sessions | Multi-session support for concurrent chats |
| Export Service | Multi-format export (text, Markdown, JSON) |
| User Memory | Custom memory CRUD with overview screen |
| Conversation Search | Inter-conversation search across history |
| Identity Config | Agent name, avatar, skills, and sources editor |
| Memory Management | Memory system controls and diagnostics |
| Platform Adaptation | Web vs native capability gating |
| HuggingFace Hub Integration | Auth, model metadata, and discovery |

---

## Notes for Implementers

### Architecture Guidelines (from AGENTS.md)

- **Singleton pattern** for services: class MyService { static MyService? _instance; static MyService get instance => _instance ??= MyService._(); MyService._(); }
- **Stream-based communication**: Use StreamController<String>.broadcast() for status updates
- **Platform channels** for native functionality: static const _channel = MethodChannel('dev.nova.assistant/tools');
- **Always close streams** in dispose()
- **Check mounted** before setState in async callbacks
- **Use withValues()** instead of withOpacity() for colors
- **Trailing commas** on multi-line parameters (enforced by analysis_options.yaml)

### Testing Guidelines

- Mirror lib/ structure in test/
- Use mockito for mocking dependencies
- Run flutter test before committing
- Run flutter analyze and dart format . before committing

### PR Checklist

- [ ] flutter analyze — no errors
- [ ] dart format . — consistent formatting
- [ ] flutter test — all tests pass
- [ ] No debug prints in production code
- [ ] No hardcoded strings (use constants)
- [ ] Trailing commas on multi-line parameters
- [ ] Update this file if a new suggestion is implemented

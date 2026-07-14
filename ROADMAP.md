# Nova Assistant Roadmap

This document outlines the planned features and improvements for Nova Assistant.

---

## Current Status (v0.2.0)

- [x] Basic chat interface with streaming responses
- [x] Multiple AI model support (SmolLM, FastVLM, Gemma 3, Gemma 4)
- [x] Automatic model selection based on query complexity
- [x] Voice input via speech-to-text
- [x] Screen capture and image attachment
- [x] Tool execution (alarms, apps, web search, weather, SMS)
- [x] RAG memory for conversation context
- [x] Custom memories system
- [x] Agent identity customization
- [x] Assistant roles (helpful, coder, creative, student, analyst)
- [x] Model download and management
- [x] Dark theme UI
- [x] Fix model re-download bug (canonical filename consistency)
- [x] Fix tool call truncation (fullResponse cleanup, multi-call support, string args)
- [x] Error handling improvements (ModelException hierarchy, retry/settings action chips)
- [x] File/URL attachment support
- [x] Conversation export (JSON/text)
- [x] Search in history
- [x] Message timestamps and copy support
- [x] Message reactions (data model, rendering, picker UI)
- [x] Battery optimization (idle model release, lifecycle-aware suspend)
- [x] Offline mode indicator with direct Install button
- [x] Context window management (token-budget truncation)
- [x] Tool call visualization (executing/done chips in ChatBubble)
- [x] Model performance metrics (Stopwatch-based inference time)
- [x] MCP-like integration (platform-channel tools + JSON schema definitions)
- [x] Code syntax highlighting (MarkdownStyleSheet enhancement)
- [x] Onboarding flow (welcome, mode selection, beginner setup wizard)
- [x] Beginner/Expert mode system (simplified UI for beginners)
- [x] Model Browser with HuggingFace search and download
- [x] Custom model import from file (.litertlm, .task, .gguf)
- [x] Model selector bottom sheet (auto/manual toggle)
- [x] Debug mode with verbose logging
- [x] HuggingFace token configuration for authenticated downloads
- [x] External tool provider abstraction (HTTP, MCP, Local)
- [x] Multi-turn tool call loop (up to 5 sequential rounds)

---

## Phase 1: Stability and Polish

### High Priority

- [x] **Fix model re-download** - Canonical filename consistency across install/detection paths
- [x] **Fix tool call truncation** - Clean fullResponse, multi-call support, string args
- [x] **Error handling improvements** - `ModelException` hierarchy with actionable suggestions, error bubbles with retry/settings action chips
- [x] **Memory management** - Optimized RAG memory retrieval with recency weighting, length normalization, and entry truncation
- [x] **Battery optimization** - 5-minute idle model release, lifecycle-aware suspend, Settings toggle
- [x] **Offline mode indicator** - Red banner when no model installed, with direct "Install" button

### Medium Priority

- [x] **File/URL attachment** - Attach files and URLs as custom context for queries
- [x] **Conversation export** - Export chat history as JSON or text
- [x] **Search in history** - Search through past conversations
- [x] **Message timestamps** - Show full timestamps (not just time)
- [x] **Copy message** - Long-press to copy individual messages
- [x] **Message reactions** - Data model, rendering, and picker UI fully wired
- [x] **Onboarding flow** - Multi-screen wizard: welcome, mode selection, beginner setup (name, permissions, model download, ready)
- [x] **Beginner/Expert mode** - `UserMode` system with simplified `AssistantScreenBeginner` UI
- [x] **Model Browser** - HuggingFace API search with download for built-in and custom models
- [x] **Custom model import** - Import `.litertlm`, `.task`, `.gguf` files via `file_picker`
- [x] **Model selector sheet** - Bottom sheet with auto/manual toggle and model cards
- [x] **Debug mode** - Settings toggle with verbose `[DEBUG]` logging in orchestrator
- [x] **HuggingFace token** - Settings dialog for authenticated model downloads
- [x] **External tool providers** - `ExternalToolProvider` factory pattern (HTTP, MCP, Local)

---

## Phase 2: Enhanced Intelligence

### High Priority

- [x] **Context window management** - Smart truncation via `clearHistory(replayHistory:)` when conversation exceeds 60% token budget
- [x] **Multi-turn tool calls** - Sequential tool execution loop (up to 5 rounds) in `ModelOrchestrator.processMessage()`
- [x] **Tool call visualization** - Tool call chips in `ChatBubble` show executing/done state
- [ ] **Streaming tool results** - Real-time updates during tool execution via platform channels (see [doc/PLAN-features.md](doc/PLAN-features.md))
- [x] **Model performance metrics** - `Stopwatch`-based inference time tracking shown per response
- [x] **MCP-like integration** - External tools via platform channels + JSON schema tool definitions
- [x] **Auto-model selection** - `ModelSelector.selectForQuery` routes by length, vision, thinking mode

### Medium Priority

- [ ] **Semantic search** - Vector-based conversation retrieval (currently keyword + recency scoring)
- [ ] **Conversation summaries** - Automatic conversation summarization
- [ ] **Proactive suggestions** - AI-suggested quick actions based on context
- [ ] **Multi-language support** - Detect and respond in user's language
- [x] **Code syntax highlighting** - Enhanced code block rendering via `MarkdownStyleSheet`
- [ ] **Custom knowledge bases** - Load and query custom document collections

---

## Phase 3: Platform Expansion

### High Priority

- [ ] **Windows support** - Native Windows application
- [ ] **Linux support** - Native Linux application
- [ ] **Watch companion** - Basic query/response on smartwatches
- [ ] **Widget support** - Home screen widgets for quick queries
- [ ] **Notification actions** - Respond to queries from notifications

### Medium Priority

- [ ] **Voice synthesis** - Text-to-speech for responses
- [ ] **Wake word detection** - "Hey Nova" voice activation
- [ ] **Real-time translation** - Live translation during conversations

---

## Phase 4: Advanced Features

### High Priority

- [ ] **Multi-modal input** - Support for audio, video, and document input
- [ ] **Plugin system** - User-created tools and integrations
- [ ] **Cloud sync** - Optional encrypted sync across devices
- [ ] **MCP client** - Full Model Context Protocol client for external tool servers

### Medium Priority

- [ ] **Collaboration** - Share conversations with other Nova users
- [ ] **Learning mode** - Teach Nova custom responses and behaviors
- [ ] **Custom tool creation** - UI for defining new tools without code

---

## Phase 5: Ecosystem

### High Priority

- [ ] **Nova API** - Public API for third-party integrations
- [ ] **MCP server support** - Model Context Protocol compatibility
- [ ] **Home automation** - Smart home device control
- [ ] **Calendar integration** - Event creation and management

### Medium Priority

- [ ] **Email integration** - Read and compose emails
- [ ] **Task management** - Create and track to-do items (see [doc/PLAN-features.md](doc/PLAN-features.md))
- [ ] **Note taking** - Create and organize notes (see [doc/PLAN-features.md](doc/PLAN-features.md))
- [ ] **Document analysis** - PDF and document understanding (see [doc/PLAN-features.md](doc/PLAN-features.md))

---

## Technical Debt

### Code Quality

- [ ] **Unit test coverage** - Increase coverage to 80%+ (currently ~10 test files covering models, services, tools, widgets)
- [ ] **Widget tests** - Add comprehensive widget tests (only `chat_bubble_test.dart` exists)
- [ ] **Integration tests** - End-to-end testing suite
- [ ] **Performance profiling** - Regular performance audits
- [ ] **Code documentation** - Comprehensive API documentation
- [ ] **Beginner mode tests** - Add tests for `AssistantScreenBeginner` and `UserPreferencesService`

### Architecture

- [ ] **State management** - Evaluate Riverpod or Bloc migration
- [ ] **Dependency injection** - Implement proper DI container
- [ ] **Navigation** - Migrate to GoRouter for better deep linking
- [ ] **Localization** - Implement i18n for multi-language support

### Build and CI/CD

- [x] **Release workflow** - GitHub Actions release.yml for tag-based APK builds
- [ ] **CI testing workflow** - GitHub Actions for automated `flutter test` and `flutter analyze` on PRs
- [ ] **Automated releases** - Streamlined release process (currently manual tag trigger)
- [ ] **Crash reporting** - Optional crash analytics (opt-in)

---

## Model Roadmap

### Current Models

| Model | Status | Notes |
|-------|--------|-------|
| SmolLM-135M | Stable | Fast, lightweight, tool support |
| FastVLM-0.5B | Stable | Vision capable |
| Gemma 3 1B | Stable | Balanced performance |
| Gemma 4 E2B | Stable | Most capable, vision + thinking |

### Planned Models

| Model | Status | Notes |
|-------|--------|-------|
| Gemma 4 E4B | Planned | Larger context window |
| Llama 3.2 | Planned | Alternative architecture |
| Phi-3 | Planned | Microsoft's compact model |
| Mistral | Planned | European AI model |

---

## Release Schedule

### v0.2.0 (Current)
- ~~Fix model re-download bug (canonical filename)~~
- ~~Fix tool call truncation (fullResponse cleanup, multi-call)~~
- ~~Error handling improvements~~ (`ModelException` hierarchy with retry/settings chips)
- ~~Battery optimization~~ (idle release, lifecycle-aware, Settings toggle)
- ~~File/URL attachments~~
- ~~Conversation export~~
- ~~Search in history~~
- ~~Message timestamps~~
- ~~Copy message~~
- ~~Message reactions~~ (data model, rendering, and picker UI)
- ~~Memory management optimization~~ (recency-weighted scoring, entry truncation)
- ~~Onboarding flow~~ (welcome, mode selection, beginner setup wizard)
- ~~Beginner/Expert mode~~ (simplified UI + mode switching)
- ~~Model Browser~~ (HuggingFace search + download)
- ~~Custom model import~~ (.litertlm, .task, .gguf via file picker)
- ~~Model selector sheet~~ (auto/manual toggle)
- ~~Debug mode~~ (verbose logging)
- ~~HuggingFace token config~~
- ~~External tool provider abstraction~~ (HTTP, MCP, Local)

### v0.3.0
- ~~MCP-like data source integration~~ (platform-channel tools + JSON schemas)
- ~~Auto-model selection based on content type~~ (`ModelSelector.selectForQuery`)
- ~~Tool call visualization~~ (executing/done chips in `ChatBubble`)
- ~~Context window management~~ (token-budget truncation via `clearHistory(replayHistory:)`)
- ~~Model performance metrics~~ (Stopwatch-based `inferenceTimeMs`)
- ~~Multi-turn sequential tool execution~~ (5-round loop in `processMessage`)
- Streaming tool results via platform channels
- Semantic conversation search (vector-based RAG)
- CI testing workflow (automated flutter test + analyze)
- Unit test coverage to 80%+

### v0.4.0
- Windows support
- Linux support
- Voice synthesis
- Wake word detection
- Plugin system
- Conversation summaries
- Proactive suggestions

### v1.0.0
- Stable release with comprehensive features
- Complete documentation
- Cloud sync
- MCP client
- Multi-language support

---

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Priority Areas

1. **Testing** - Write unit, widget, and integration tests
2. **Windows/Linux development** - Help bring Nova to desktop platforms
3. **Documentation** - Improve guides and API documentation
4. **Localization** - Help translate Nova into other languages
5. **Bug fixes** - Check our [issue tracker](https://github.com/yourusername/nova_assistant/issues)

---

## Feedback

We value your input! Please share your ideas and feedback:

- **GitHub Issues** - Report bugs and request features
- **Discussions** - Share ideas and ask questions
- **Discord** - Join our community chat

---

## License

This roadmap is subject to change based on community feedback and technical requirements.

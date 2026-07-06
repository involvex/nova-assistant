# Nova Assistant Roadmap

This document outlines the planned features and improvements for Nova Assistant.

---

## Current Status (v0.1.0)

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

---

## Phase 1: Stability and Polish

### High Priority

- [ ] **Fix refreshSettings method** - Resolve the missing `refreshSettings` method in ModelOrchestrator
- [ ] **Error handling improvements** - Better error messages and recovery for model loading failures
- [ ] **Memory management** - Optimize RAG memory retrieval and reduce memory usage
- [ ] **Battery optimization** - Reduce power consumption during inference
- [ ] **Offline mode indicator** - Clear UI feedback when models are unavailable

### Medium Priority

- [ ] **Conversation export** - Export chat history as JSON or text
- [ ] **Search in history** - Search through past conversations
- [ ] **Message timestamps** - Show full timestamps (not just time)
- [ ] **Copy message** - Long-press to copy individual messages
- [ ] **Message reactions** - Thumbs up/down for feedback

---

## Phase 2: Enhanced Intelligence

### High Priority

- [ ] **Context window management** - Smart truncation for long conversations
- [ ] **Multi-turn tool calls** - Support for sequential tool execution
- [ ] **Tool call visualization** - Show tool calls and results in the UI
- [ ] **Streaming tool results** - Real-time updates during tool execution
- [ ] **Model performance metrics** - Track inference time and token usage

### Medium Priority

- [ ] **Semantic search** - Vector-based conversation retrieval
- [ ] **Conversation summaries** - Automatic conversation summarization
- [ ] **Proactive suggestions** - AI-suggested quick actions based on context
- [ ] **Multi-language support** - Detect and respond in user's language
- [ ] **Code syntax highlighting** - Enhanced code block rendering

---

## Phase 3: Platform Expansion

### High Priority

- [ ] **iOS support** - Native iOS implementation
- [ ] **macOS support** - Desktop application
- [ ] **Windows support** - Native Windows application
- [ ] **Linux support** - Native Linux application

### Medium Priority

- [ ] **Watch companion** - Basic query/response on smartwatches
- [ ] **Car integration** - Android Auto / Apple CarPlay support
- [ ] **Widget support** - Home screen widgets for quick queries
- [ ] **Notification actions** - Respond to queries from notifications

---

## Phase 4: Advanced Features

### High Priority

- [ ] **Multi-modal input** - Support for audio, video, and document input
- [ ] **Real-time translation** - Live translation during conversations
- [ ] **Voice synthesis** - Text-to-speech for responses
- [ ] **Wake word detection** - "Hey Nova" voice activation

### Medium Priority

- [ ] **Plugin system** - User-created tools and integrations
- [ ] **Cloud sync** - Optional encrypted sync across devices
- [ ] **Collaboration** - Share conversations with other Nova users
- [ ] **Learning mode** - Teach Nova custom responses and behaviors

---

## Phase 5: Ecosystem

### High Priority

- [ ] **Nova API** - Public API for third-party integrations
- [ ] **MCP server support** - Model Context Protocol compatibility
- [ ] **Home automation** - Smart home device control
- [ ] **Calendar integration** - Event creation and management

### Medium Priority

- [ ] **Email integration** - Read and compose emails
- [ ] **Task management** - Create and track to-do items
- [ ] **Note taking** - Create and organize notes
- [ ] **Document analysis** - PDF and document understanding

---

## Technical Debt

### Code Quality

- [ ] **Unit test coverage** - Increase coverage to 80%+
- [ ] **Widget tests** - Add comprehensive widget tests
- [ ] **Integration tests** - End-to-end testing suite
- [ ] **Performance profiling** - Regular performance audits
- [ ] **Code documentation** - Comprehensive API documentation

### Architecture

- [ ] **State management** - Evaluate Riverpod or Bloc migration
- [ ] **Dependency injection** - Implement proper DI container
- [ ] **Navigation** - Migrate to GoRouter for better deep linking
- [ ] **Localization** - Implement i18n for multi-language support

### Build and CI/CD

- [ ] **GitHub Actions** - Automated testing and builds
- [ ] **Code signing** - Proper release signing setup
- [ ] **Automated releases** - Streamlined release process
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

### v0.2.0 (Next Release)
- Fix refreshSettings method
- Error handling improvements
- Battery optimization
- Conversation export

### v0.3.0
- Tool call visualization
- Context window management
- Multi-turn tool calls
- Model performance metrics

### v0.4.0
- iOS support
- macOS support
- Voice synthesis
- Wake word detection

### v1.0.0
- Stable release across all platforms
- Complete documentation
- Plugin system
- Cloud sync

---

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Priority Areas

1. **iOS/macOS development** - Help bring Nova to Apple platforms
2. **Testing** - Write unit, widget, and integration tests
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

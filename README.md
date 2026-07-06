# Nova Assistant

> An on-device AI assistant powered by Gemma, built with Flutter.

Nova runs AI models entirely on your device - no data is sent to external servers. Get fast, private AI assistance with voice input, screen awareness, and tool execution capabilities.

## Features

- **On-Device AI** - All inference runs locally using Gemma models via `flutter_gemma`
- **Multiple Models** - Automatic model selection based on query complexity and capabilities
- **Voice Input** - Speak to Nova using speech-to-text transcription
- **Screen Capture** - Share your screen context with the assistant
- **Tool Execution** - Set alarms, open apps, search the web, and more
- **RAG Memory** - Nova remembers past conversations for contextual responses
- **Custom Memories** - Add personal information Nova should remember
- **Agent Identity** - Customize Nova's name, avatar, skills, and knowledge sources
- **Multiple Roles** - Helpful, Coder, Creative, Student, or Analyst personas

## Supported Models

| Model | Size | Vision | Thinking | Tools | Format |
|-------|------|--------|----------|-------|--------|
| SmolLM-135M | 135MB | No | No | Yes | .task |
| FastVLM-0.5B | 500MB | Yes | No | Yes | .litertlm |
| Gemma 3 1B | 500MB | No | No | Yes | .litertlm |
| Gemma 4 E2B | 2400MB | Yes | Yes | Yes | .litertlm |

## Getting Started

### Prerequisites

- Flutter SDK >=3.44.0
- Dart SDK >=3.12.0 <4.0.0
- Android Studio or VS Code
- Android device or emulator (API 26+)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/nova_assistant.git
cd nova_assistant
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

### Building

```bash
# Android APK (debug)
flutter build apk --debug

# Android APK (release)
flutter build apk --release

# Web
flutter build web --release
```

## Project Structure

```
nova_assistant/
  lib/
    main.dart                    # App entry point
    models/                      # Data models
    screens/                     # UI screens
    services/                    # Business logic
    platform/                    # Platform channels
    tools/                       # AI tool definitions
    widgets/                     # Reusable UI components
  test/                          # Tests
  android/                       # Android native code
```

## Architecture

### Core Patterns

- **Singleton Services** - Services use lazy singleton initialization
- **Stream-Based Communication** - Services communicate via broadcast streams
- **Platform Channels** - Native functionality via MethodChannel

### Model Selection

Nova automatically selects the best model based on your query:
- Short queries (<8 words) use SmolLM for fast responses
- Image input switches to FastVLM or Gemma 4 (vision-capable)
- Thinking mode uses Gemma 4 E2B (reasoning-capable)
- Complex queries default to Gemma 4 E2B (most capable)

### Available Tools

| Tool | Description |
|------|-------------|
| `get_time` | Get current time, date, and day |
| `set_alarm` | Set a device alarm |
| `cancel_alarm` | Cancel an existing alarm |
| `open_app` | Open an app by package name |
| `search_web` | Open browser with search query |
| `get_weather` | Get weather for a location |
| `send_sms` | Send an SMS message |
| `open_settings` | Open device Settings |
| `take_screenshot` | Capture current screen |

## Privacy

- **100% On-Device** - All AI inference runs locally
- **No Data Collection** - No analytics or telemetry
- **Local Storage** - Chat history stored via SharedPreferences
- **Trusted Sources** - Models downloaded from HuggingFace

## Platform Support

| Platform | Status |
|----------|--------|
| Android | Fully supported |
| Web | Limited (no vision, thinking, or tools) |
| Windows | Experimental |

## Development

### Commands

```bash
# Install dependencies
flutter pub get

# Run tests
flutter test

# Run tests with coverage
flutter test --coverage

# Analyze code
flutter analyze

# Format code
dart format .
```

### Code Style

This project enforces strict Dart style via `analysis_options.yaml`. Key rules:
- Prefer `final` for local variables
- Always use trailing commas
- Use `const` constructors when possible
- Prefer `SizedBox` over `Container` for spacing

See [AGENTS.md](AGENTS.md) for complete coding guidelines.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Flutter](https://flutter.dev/) - Cross-platform UI framework
- [flutter_gemma](https://pub.dev/packages/flutter_gemma) - On-device AI inference
- [Gemma](https://ai.google.dev/gemma) - Google's open-source AI models
- [HuggingFace](https://huggingface.co/) - Model hosting and distribution

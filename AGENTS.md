# AGENTS.md - Nova Assistant

> **Nova** is an on-device AI assistant powered by Gemma, built with Flutter.
> All AI inference runs locally on the device - no data is sent to external servers.

**Human docs:** [`docs/`](docs/) (GitHub Pages) · **Agent skill:** [`.cursor/skills/nova-dev`](.cursor/skills/nova-dev/SKILL.md)

When a developer says *use the nova_dev skill to setup and build the app* or
*configure my own model*, follow that skill first, then this file for coding standards.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Technologies](#technologies)
- [Useful Commands](#useful-commands)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Coding Standards and Best Practices](#coding-standards-and-best-practices)
- [Testing Guidelines](#testing-guidelines)
- [Git Conventions](#git-conventions)
- [Platform Notes](#platform-notes)
- [Security Considerations](#security-considerations)
- [Key Models Reference](#key-models-reference)
- [Available Tools](#available-tools)
- [Assistant Roles](#assistant-roles)

---

## Project Overview

Nova is a Flutter-based mobile AI assistant that:

- Runs AI models entirely on-device using `flutter_gemma`
- Supports multiple inference engines (LiteRtLm, MediaPipe)
- Provides voice input, screen capture, and tool execution capabilities
- Uses RAG (Retrieval-Augmented Generation) with local memory
- Supports multiple AI models with automatic selection

---

## Technologies

### Core Framework

| Technology | Version | Purpose |
|------------|---------|---------|
| **Flutter** | >=3.44.0 | Cross-platform UI framework |
| **Dart** | >=3.12.0 <4.0.0 | Programming language |
| **Kotlin** | JVM 17 | Android native code |

### AI and Inference

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_gemma` | ^1.2.0 | Core Gemma inference engine |
| `flutter_gemma_litertlm` | 1.0.2 | LiteRT LM inference backend |
| `flutter_gemma_mediapipe` | 1.0.3 | MediaPipe inference backend |

### Storage and Persistence

| Package | Version | Purpose |
|---------|---------|---------|
| `shared_preferences` | ^2.3.4 | Key-value local storage |
| `sqflite` | ^2.4.1 | SQLite database |
| `path_provider` | ^2.1.5 | File system paths |
| `uuid` | ^4.5.1 | Unique ID generation |

### Audio and Speech

| Package | Version | Purpose |
|---------|---------|---------|
| `speech_to_text` | ^7.0.0 | Speech-to-text transcription |
| `record` | ^7.1.1 | Audio recording |
| `just_audio` | ^0.10.6 | Audio playback |

### UI and Media

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_markdown` | ^0.7.6 | Markdown rendering |
| `image_picker` | ^1.1.2 | Image selection from gallery |
| `file_picker` | ^11.0.2 | File selection |
| `permission_handler` | ^12.0.3 | Runtime permissions |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Unit and widget testing |
| `flutter_lints` | ^6.0.0 | Lint rules |
| `mockito` | ^5.4.4 | Mocking for tests |
| `build_runner` | ^2.4.13 | Code generation |
| `dart_code_linter` | ^4.1.6 | Code metrics and analysis |

---

## Useful Commands

> **Note:** Flutter and Dart commands must be run directly (e.g. `flutter test`, `dart format .`). Do **not** prefix them with `bun run`.

### Setup and Installation

```bash
# Install dependencies
flutter pub get

# Regenerate code (after model changes)
dart run build_runner build --delete-conflicting-outputs

# Check for outdated packages
flutter pub outdated
```

### Run and Debug

```bash
# Run in debug mode on connected device
flutter run

# Run on specific platform
flutter run -d android
flutter run -d windows
flutter run -d chrome

# Run with specific flavor
flutter run --flavor production

# Hot reload (while running)
r

# Hot restart (while running)
R
```

### Build and Release

```bash
# Build Android APK (debug)
flutter build apk --debug

# Build Android APK (release)
flutter build apk --release

# Build Android App Bundle
flutter build appbundle --release

# Build web
flutter build web --release

# Build Windows
flutter build windows --release
```

#### Versioned release (Windows)

```powershell
# Default: patch bump, changelog, analyze, test, arm64 release APK, commit, tag, push
./scripts/release.ps1

# Preview without changing anything
./scripts/release.ps1 -DryRun

# Minor/major, custom changelog bullet, local-only
./scripts/release.ps1 -Bump minor -Message "Settings hubs" -NoPush
./scripts/release.ps1 -SkipTests -AppBundle
```

Requires a clean git working tree and `CHANGELOG.md` with an `## [Unreleased]` section.
`pubspec.yaml` may use `MAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH+BUILD`; releases always write `+BUILD`.

### Testing

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/models/chat_message_test.dart

# Run tests with coverage
flutter test --coverage
```

### Analysis and Linting

```bash
# Run static analysis
flutter analyze

# Fix auto-fixable issues
dart fix --apply

# Check formatting
dart format --set-exit-if-changed .

# Format all files
dart format .
```

### Platform-Specific (Android)

```bash
# Clean Android build
cd android && .\gradlew.bat clean && cd ..

# Build Android debug APK
flutter build apk --debug --target-platform android-arm64

# Install on connected device
flutter install
```

---

## Project Structure

```
nova_assistant/
  lib/
    main.dart                       # App entry point and initialization
    models/                         # Data models
      agent_identity.dart           # Agent identity configuration
      assistant_role.dart           # Role-based system prompts
      chat_message.dart             # Chat message data class
      model_info.dart               # Model definitions and selection
    screens/                        # UI screens
      assistant_screen.dart         # Main chat interface
      identity_config_screen.dart   # Identity configuration
      memory_management_screen.dart # Memory management UI
      settings_screen.dart          # App settings
    services/                       # Business logic services
      chat_history_service.dart     # Chat history persistence
      download_progress_service.dart# Download tracking
      memory_service.dart           # RAG memory system
      model_manager.dart            # Model installation and management
      model_orchestrator.dart       # Inference orchestration
      model_update_service.dart     # Model update checking
      parallel_session_manager.dart # Multi-session support
      platform_adaptation_service.dart # Platform-specific adaptations
    platform/                       # Platform channel integrations
      assistant_role_service.dart   # Assistant role via platform channel
      screenshot_service.dart       # Screen capture
      tool_executor_service.dart    # Tool execution via native code
    tools/                          # Tool definitions for AI
      tool_definitions.dart         # Available tools for AI model
    widgets/                        # Reusable UI components
      chat_bubble.dart              # Chat message bubble
      voice_input.dart              # Voice input button
  test/                             # Test files (mirrors lib/ structure)
    models/
    services/
    tools/
    widgets/
  android/                          # Android-specific code
  doc/                              # Documentation
  pubspec.yaml                      # Dependencies
  analysis_options.yaml             # Lint rules
```

---

## Architecture

### Core Patterns

1. **Singleton Services**: Most services use the singleton pattern

```dart
class MyService {
  static MyService? _instance;
  static MyService get instance => _instance ??= MyService._();
  MyService._();
}
```

2. **Stream-Based Communication**: Services communicate via broadcast streams

```dart
final _statusController = StreamController<String>.broadcast();
Stream<String> get statusStream => _statusController.stream;
```

3. **Platform Channels**: Native functionality via MethodChannel

```dart
static const _channel = MethodChannel('dev.nova.assistant/tools');
```

### Model Selection Flow

```
User Query
    |
ModelSelector.selectForQuery()
    |
+-- Short query (<=8 words) --> SmolLM (fast)
+-- Image attached ----------> FastVLM or Gemma 4 (vision)
+-- Thinking mode -----------> Gemma 4 (thinking)
+-- Default -----------------> Gemma 4 E2B (heavy)
```

### Inference Pipeline

1. User sends message
2. `ModelOrchestrator.processMessage()` receives query
3. RAG context retrieved from `MemoryService`
4. Model selected based on query characteristics
5. Model loaded via `FlutterGemma.getActiveModel()`
6. Chat created with system prompt and tools
7. Response streamed via `generateChatResponseAsync()`
8. Tool calls intercepted and executed via `ToolExecutorService`
9. Tool results fed back to model for final response
10. Conversation stored in memory

### Tool System

Tools are defined as `Tool` objects with JSON schemas:

```dart
static final Tool getTime = Tool(
  name: 'get_time',
  description: 'Get the current time, date, and day of the week',
  parameters: <String, Object>{
    'type': 'object',
    'properties': <String, Object>{},
  },
);
```

Tool execution flows through platform channels to native code.

---

## Coding Standards and Best Practices

### Dart Style Guide

This project enforces **strict Dart style** via `analysis_options.yaml`.

#### Enforced Rules

- **`prefer_final_locals`**: Use `final` for local variables when possible
- **`prefer_final_fields`**: Use `final` for private fields when possible
- **`require_trailing_commas`**: Always add trailing commas
- **`always_declare_return_types`**: Explicit return types on functions
- **`annotate_overrides`**: Use `@override` annotation
- **`avoid_empty_else`**: No empty else blocks
- **`avoid_init_to_null`**: Do not initialize variables to null
- **`prefer_single_quotes`**: Use single quotes for strings
- **`prefer_const_constructors`**: Use `const` when possible
- **`sized_box_for_whitespace`**: Use `SizedBox` not `Container` for spacing
- **`sort_child_properties_last`**: Put `child` property last in widgets

#### Code Metrics (dart_code_linter)

```yaml
metrics:
  cyclomatic-complexity: 20
  number-of-parameters: 4
  maximum-nesting-level: 5
```

#### Enforced Lint Rules

- `avoid-dynamic`: Prefer specific types over `dynamic`
- `avoid-passing-async-when-sync-expected`
- `avoid-redundant-async`: Do not await futures in sync contexts
- `avoid-unnecessary-type-assertions`
- `avoid-unnecessary-type-casts`
- `avoid-unrelated-type-assertions`
- `avoid-unused-parameters`
- `avoid-nested-conditional-expressions`
- `newline-before-return`: Blank line before return
- `no-boolean-literal-compare`
- `no-empty-block`
- `prefer-trailing-comma`
- `prefer-conditional-expressions`
- `no-equal-then-else`
- `prefer-moving-to-variable`
- `prefer-match-file-name`

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Classes | PascalCase | `ModelOrchestrator`, `ChatMessage` |
| Files | snake_case | `model_orchestrator.dart` |
| Variables | camelCase | `activeModel`, `isGenerating` |
| Constants | camelCase | `_maxToolRounds`, `_prefsKey` |
| Private members | `_` prefix | `_instance`, `_statusController` |
| Enums | PascalCase | `NovaModel`, `DownloadStatus` |
| Enum values | camelCase | `NovaModel.smollm`, `DownloadStatus.downloading` |

### File Organization

```dart
// 1. Dart core imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// 2. Flutter imports
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// 3. Package imports
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 4. Project imports
import 'package:nova_assistant/models/model_info.dart';
import 'package:nova_assistant/services/model_manager.dart';
```

### Widget Guidelines

1. **Use `const` constructors** when possible
2. **Prefer `SizedBox`** over `Container` for whitespace
3. **Use `withValues()`** instead of `withOpacity()` for color
4. **Always include `key` parameter** in widget constructors
5. **Use `copyWith()`** for immutable data updates

```dart
class MyWidget extends StatelessWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 100,
      height: 100,
    );
  }
}
```

### Error Handling

```dart
// Use try-catch for async operations
try {
  final result = await someAsyncOperation();
  return result;
} on PlatformException catch (e) {
  debugPrint('Platform error: ${e.message}');
  return null;
} catch (e) {
  debugPrint('Unexpected error: $e');
  rethrow;
}

// Always check mounted before setState in async callbacks
await for (final event in stream) {
  if (!mounted) break;
  setState(() => _value = event);
}
```

### Stream Management

```dart
// Always close streams in dispose()
@override
void dispose() {
  _statusController.close();
  _subscriptions.cancel();
  super.dispose();
}

// Use broadcast streams for multiple listeners
final _controller = StreamController<String>.broadcast();
Stream<String> get stream => _controller.stream;
```

### Singleton Pattern

```dart
class MyService {
  static MyService? _instance;
  static MyService get instance => _instance ??= MyService._();
  MyService._();

  // Private constructor prevents external instantiation
}
```

---

## Testing Guidelines

### Test Structure

Mirror the `lib/` directory structure in `test/`:

```
test/
  models/
    chat_message_test.dart
  services/
    model_orchestrator_test.dart
    memory_service_test.dart
  tools/
    tool_definitions_test.dart
  widgets/
    chat_bubble_test.dart
```

### Writing Tests

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('should serialize to JSON correctly', () {
      final message = ChatMessage(
        id: '1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime(2024, 1, 1),
      );

      final json = message.toJson();

      expect(json['id'], '1');
      expect(json['text'], 'Hello');
      expect(json['isUser'], true);
    });

    test('should deserialize from JSON', () {
      final json = {
        'id': '1',
        'text': 'Hello',
        'isUser': true,
        'timestamp': '2024-01-01T00:00:00.000',
      };

      final message = ChatMessage.fromJson(json);

      expect(message.id, '1');
      expect(message.text, 'Hello');
      expect(message.isUser, true);
    });

    test('copyWith should preserve unchanged fields', () {
      final original = ChatMessage(
        id: '1',
        text: 'Hello',
        isUser: true,
        timestamp: DateTime(2024, 1, 1),
      );

      final copy = original.copyWith(text: 'World');

      expect(copy.id, '1');
      expect(copy.text, 'World');
      expect(copy.isUser, true);
    });
  });
}
```

### Mocking

Use `mockito` for mocking dependencies:

```dart
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([SharedPreferences])
import 'my_test.mocks.dart';

void main() {
  late MockSharedPreferences mockPrefs;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    when(mockPrefs.getString(any)).thenReturn(null);
  });
}
```

### Running Tests

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test
flutter test test/models/chat_message_test.dart

# Run tests matching pattern
flutter test --name "should serialize"
```

---

## Git Conventions

### Branch Naming

- `main` - Production-ready code
- `develop` - Integration branch
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation changes

### Commit Messages

Follow Conventional Commits:

```
feat: add parallel session management
fix: resolve model loading timeout
docs: update AGENTS.md
refactor: extract model selection logic
test: add unit tests for ChatMessage
chore: update dependencies
```

### Pre-Commit Checklist

- Run `flutter analyze` - no errors
- Run `dart format .` - consistent formatting
- Run `flutter test` - all tests pass
- No debug prints in production code
- No hardcoded strings (use constants)
- Trailing commas on multi-line parameters

---

## Platform Notes

### Android

- **Min SDK**: 26 (Android 8.0)
- **Target SDK**: Latest Flutter default
- **NDK Version**: 28.2.13676358
- **ABI Filter**: `arm64-v8a` only (64-bit devices)
- **Java/Kotlin**: JVM 17

### Web Limitations

The web platform has several limitations:

- Vision/image input not supported on web litertlm
- Thinking mode not supported on web litertlm
- Function calling not supported on web litertlm
- Chrome has approximately 2GB ArrayBuffer limit for model storage
- Use MediaPipe `.task` models for web vision/thinking/function calling support

---

## Security Considerations

### Data Privacy

- All AI inference runs **entirely on-device** - no data is sent to external servers
- Chat history is stored locally via SharedPreferences
- Model files are stored in the app's documents directory
- No analytics or telemetry by default
- Exception: the `webfetch` tool makes an outbound HTTP(S) request **only when
  the user asks to read a specific link** (the query must contain a URL or
  fetch/read phrasing). Only the requested page content enters model context;
  nothing else is transmitted.

### Permissions

The app requests the following permissions:

- **Microphone**: For voice input (speech-to-text)
- **Photos**: For image picking from gallery
- **Screen Capture**: For screenshot-based context (requires user consent)

### Model Security

- Models are downloaded from trusted HuggingFace repositories
- Model files are verified after download
- Download retry logic with exponential backoff
- Models can be uninstalled to free storage

### Best Practices

- Never log sensitive user data in debug output
- Clear `debugPrint` statements before release builds
- Use `flutter build apk --obfuscate` for release builds
- Do not commit API keys or secrets to version control
- Use environment variables for sensitive configuration

---

## Key Models Reference

| Model | Size | Vision | Thinking | Function Calling | Format |
|-------|------|--------|----------|------------------|--------|
| SmolLM-135M | 135MB | No | No | Yes | .task |
| FastVLM-0.5B | 500MB | Yes | No | Yes | .litertlm |
| Gemma 3 1B | 500MB | No | No | Yes | .litertlm |
| Gemma 4 E2B | 2400MB | Yes | Yes | Yes | .litertlm |

### Model Selection Logic

- **Short queries** (<=8 words): Use SmolLM for fast response
- **Image input**: Use FastVLM or Gemma 4 E2B (vision capable)
- **Thinking mode**: Use Gemma 4 E2B (thinking capable)
- **Complex queries**: Use Gemma 4 E2B (most capable)

---

## Available Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_time` | Get current time, date, and day | None |
| `set_alarm` | Set a device alarm | hour, minute, message |
| `cancel_alarm` | Cancel an existing alarm | hour, minute |
| `open_app` | Open an app by package name | package |
| `search_web` | Open browser with search query | query |
| `webfetch` | Fetch a URL and read its page content (HTML converted to plain text) | url, max_length |
| `get_weather` | Get weather for a location | location |
| `send_sms` | Send an SMS message | phone, message |
| `open_settings` | Open device Settings | None |
| `take_screenshot` | Capture current screen | None |

---

## Assistant Roles

| Role | Description |
|------|-------------|
| `helpful` | General helpful assistant (default) |
| `coder` | Expert programming assistant |
| `creative` | Creative writing assistant |
| `student` | Study companion |
| `analyst` | Data analysis assistant |

Each role has a custom system prompt that shapes the AI's behavior and personality.

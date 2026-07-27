# Feature Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 7 features from suggestions.md: In-Chat Search, Pull-to-Refresh, Screen Timeout During Streaming, Message Copy with Attribution, Model Storage Breakdown, Chat Bubble Themes, and Battery-Aware Model Switching.

**Architecture:** Each feature is self-contained and modifies existing files without cross-dependencies. Features are ordered from simplest to most complex to build momentum.

**Tech Stack:** Flutter/Dart, SharedPreferences, MethodChannel (for battery level)

## Global Constraints

- Dart >=3.12.0 <4.0.0
- Flutter >=3.44.0
- Use `withValues()` instead of `withOpacity()` for colors
- Trailing commas on all multi-line parameters
- Use `prefer_final_locals` — declare `final` where possible
- Use single quotes for strings
- Mirror `lib/` structure in `test/`
- Run `flutter analyze` and `dart format .` before committing

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `lib/screens/assistant_screen.dart` | Modify | Add in-chat search bar, pull-to-refresh, screen timeout, copy with attribution |
| `lib/widgets/chat_bubble.dart` | Modify | Add bubble themes, copy with attribution |
| `lib/screens/settings_screen.dart` | Modify | Add bubble theme picker, model storage breakdown, screen timeout toggle |
| `lib/models/user_preferences.dart` | Modify | Add `bubbleTheme` and `screenTimeoutDuringStream` fields |
| `lib/services/user_preferences_service.dart` | Modify | Add getters/setters for new preferences |
| `lib/services/model_orchestrator.dart` | Modify | Add battery-aware model switching, expose battery level |
| `lib/services/model_manager.dart` | Modify | Add method to get storage breakdown per model |
| `lib/services/platform_adaptation_service.dart` | Modify | Add battery level monitoring |
| `lib/models/chat_bubble_theme.dart` | Create | Bubble theme definitions |
| `lib/utils/bubble_theme_provider.dart` | Create | Theme color provider |
| `lib/widgets/in_chat_search_bar.dart` | Create | Reusable in-chat search widget |
| `test/models/chat_bubble_theme_test.dart` | Create | Theme model tests |
| `test/utils/bubble_theme_provider_test.dart` | Create | Theme provider tests |

---

## Feature 1: Message Copy with Attribution

**Goal:** When copying an assistant message, include model name and timestamp.

### Task 1: Add attribution to copy action

**Files:**
- Modify: `lib/screens/assistant_screen.dart:2471-2475`
- Modify: `lib/screens/assistant_screen_beginner.dart:420-423`

**Interfaces:**
- Consumes: `ChatMessage` fields (text, modelName, timestamp)
- Produces: Updated clipboard content with attribution string

- [ ] **Step 1: Locate the existing copy action in assistant_screen.dart**

The copy action is at line ~2471:
```dart
Clipboard.setData(ClipboardData(text: msg.text));
```

- [ ] **Step 2: Replace the copy logic with attributed copy**

```dart
// In assistant_screen.dart, replace the copy action around line 2471
final attribution = msg.isUser
    ? ''
    : '\n\n— ${msg.modelName ?? "Nova"} · ${_formatTimestamp(msg.timestamp)}';
Clipboard.setData(ClipboardData(text: '${msg.text}$attribution'));
```

- [ ] **Step 3: Add the same logic to assistant_screen_beginner.dart**

```dart
// In assistant_screen_beginner.dart, replace the copy action around line 420
final attribution = msg.isUser
    ? ''
    : '\n\n— ${msg.modelName ?? "Nova"} · ${_formatTimestamp(msg.timestamp)}';
Clipboard.setData(ClipboardData(text: '${msg.text}$attribution'));
```

- [ ] **Step 4: Add a helper method if `_formatTimestamp` doesn't exist**

Check if `_formatTimestamp` exists in both files. If not, add:
```dart
String _formatTimestamp(DateTime? timestamp) {
  if (timestamp == null) return '';
  final now = DateTime.now();
  final diff = now.difference(timestamp);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
}
```

- [ ] **Step 5: Run analysis and format**

Run: `flutter analyze lib/screens/assistant_screen.dart lib/screens/assistant_screen_beginner.dart`
Expected: No new errors

- [ ] **Step 6: Commit**

```bash
git add lib/screens/assistant_screen.dart lib/screens/assistant_screen_beginner.dart
git commit -m "feat: add model name and timestamp attribution when copying messages"
```

---

## Feature 2: Pull-to-Refresh Conversation List

**Goal:** Add pull-to-refresh gesture to the conversation list in chat history.

### Task 2: Add RefreshIndicator to conversation list

**Files:**
- Modify: `lib/screens/chat_history_screen.dart`

**Interfaces:**
- Consumes: `ChatHistoryService.load()`
- Produces: Refreshed conversation list

- [ ] **Step 1: Locate the conversation ListView in chat_history_screen.dart**

Find the `ListView.builder` that displays conversations. It should be inside a `State` class.

- [ ] **Step 2: Wrap the ListView with RefreshIndicator**

```dart
// Replace the bare ListView.builder with:
RefreshIndicator(
  onRefresh: () async {
    await _loadConversations();
    if (mounted) setState(() {});
  },
  child: ListView.builder(
    // ... existing builder code ...
  ),
)
```

- [ ] **Step 3: Ensure `_loadConversations` exists and is async**

Check if `_loadConversations` exists. If not, look for the method that loads conversations and use that. The method should call `ChatHistoryService.load()` or equivalent.

- [ ] **Step 4: Run analysis**

Run: `flutter analyze lib/screens/chat_history_screen.dart`
Expected: No new errors

- [ ] **Step 5: Commit**

```bash
git add lib/screens/chat_history_screen.dart
git commit -m "feat: add pull-to-refresh to conversation list"
```

---

## Feature 3: Screen Timeout During Streaming

**Goal:** Keep the screen awake while the model is streaming a response.

### Task 3: Add screen timeout preference and implementation

**Files:**
- Modify: `lib/screens/settings_screen.dart` (add toggle)
- Modify: `lib/screens/assistant_screen.dart` (apply Wakelock)
- Add: `wakelock_plus` to `pubspec.yaml` (check if already present)

**Interfaces:**
- Consumes: `SharedPreferences` key `settings_screen_timeout_stream`
- Produces: Screen stays on during streaming

- [ ] **Step 1: Check if wakelock_plus is already in pubspec.yaml**

Run: `grep -n "wakelock" pubspec.yaml`
If not present, add it:
```yaml
dependencies:
  wakelock_plus: ^1.2.0
```

Then run: `flutter pub get`

- [ ] **Step 2: Add toggle to settings_screen.dart**

In the `_appHubChildren()` method (or appearance hub), add a toggle tile:
```dart
_toggleTile(
  icon: Icons.screen_lock_portrait_outlined,
  title: 'Keep screen on during streaming',
  subtitle: 'Prevent screen timeout while assistant is responding',
  value: _screenTimeoutStream,
  onChanged: (v) {
    setState(() => _screenTimeoutStream = v);
    _saveSetting('settings_screen_timeout_stream', v);
  },
),
```

Also add the field to the `State` class and load it in `_loadSettings()`:
```dart
bool _screenTimeoutStream = true;
// In _loadSettings():
_screenTimeoutStream = prefs.getBool('settings_screen_timeout_stream') ?? true;
```

- [ ] **Step 3: Apply wakelock in assistant_screen.dart**

Import wakelock_plus:
```dart
import 'package:wakelock_plus/wakelock_plus.dart';
```

In the streaming logic, when streaming starts:
```dart
// When _isStreaming becomes true:
final prefs = await SharedPreferences.getInstance();
if (prefs.getBool('settings_screen_timeout_stream') ?? true) {
  WakelockPlus.enable();
}
```

When streaming ends (in the completion/error handler):
```dart
WakelockPlus.disable();
```

Also disable in `dispose()`:
```dart
@override
void dispose() {
  WakelockPlus.disable();
  // ... existing dispose code
}
```

- [ ] **Step 4: Run analysis**

Run: `flutter analyze lib/screens/assistant_screen.dart lib/screens/settings_screen.dart`
Expected: No new errors

- [ ] **Step 5: Commit**

```bash
git add lib/screens/assistant_screen.dart lib/screens/settings_screen.dart pubspec.yaml pubspec.lock
git commit -m "feat: add screen timeout control during streaming"
```

---

## Feature 4: In-Chat Message Search

**Goal:** Add a search bar overlay to filter messages within the current conversation thread.

### Task 4: Create the in-chat search widget

**Files:**
- Create: `lib/widgets/in_chat_search_bar.dart`

**Interfaces:**
- Consumes: List of messages, callback for filter
- Produces: Search bar UI with match count and navigation

- [ ] **Step 1: Create the search bar widget**

```dart
// lib/widgets/in_chat_search_bar.dart
import 'package:flutter/material.dart';

class InChatSearchBar extends StatefulWidget {
  const InChatSearchBar({
    super.key,
    required this.onSearch,
    required this.onClose,
    this.matchCount = 0,
    this.currentMatch = 0,
    this.onNext,
    this.onPrevious,
  });

  final ValueChanged<String> onSearch;
  final VoidCallback onClose;
  final int matchCount;
  final int currentMatch;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  @override
  State<InChatSearchBar> createState() => _InChatSearchBarState();
}

class _InChatSearchBarState extends State<InChatSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search in conversation...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixText: widget.matchCount > 0
                      ? '${widget.currentMatch}/${widget.matchCount}'
                      : null,
                  suffixStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: const Color(0xFF0D0D1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: widget.onSearch,
              ),
            ),
            if (widget.matchCount > 1) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70),
                onPressed: widget.onPrevious,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                onPressed: widget.onNext,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () {
                _controller.clear();
                widget.onSearch('');
                widget.onClose();
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analysis on the new widget**

Run: `flutter analyze lib/widgets/in_chat_search_bar.dart`
Expected: No errors

- [ ] **Step 3: Commit the widget**

```bash
git add lib/widgets/in_chat_search_bar.dart
git commit -m "feat: add InChatSearchBar widget for in-conversation search"
```

---

### Task 5: Integrate in-chat search into assistant_screen.dart

**Files:**
- Modify: `lib/screens/assistant_screen.dart`

**Interfaces:**
- Consumes: `InChatSearchBar` widget, message list
- Produces: Filtered message view with match highlighting

- [ ] **Step 1: Add state variables to assistant_screen.dart**

In the `_AssistantScreenState` class, add:
```dart
bool _showSearch = false;
String _searchQuery = '';
int _searchMatchCount = 0;
int _currentSearchMatch = 0;
List<int> _searchMatchIndices = [];
```

- [ ] **Step 2: Add search method**

```dart
void _filterMessages(String query) {
  setState(() {
    _searchQuery = query;
    if (query.isEmpty) {
      _searchMatchIndices = [];
      _searchMatchCount = 0;
      _currentSearchMatch = 0;
      return;
    }
    final lower = query.toLowerCase();
    _searchMatchIndices = _messages
        .asMap()
        .entries
        .where((e) => e.value.text.toLowerCase().contains(lower))
        .map((e) => e.key)
        .toList();
    _searchMatchCount = _searchMatchIndices.length;
    _currentSearchMatch = _searchMatchCount > 0 ? 1 : 0;
  });
}

void _nextSearchMatch() {
  if (_searchMatchIndices.isEmpty) return;
  setState(() {
    _currentSearchMatch = _currentSearchMatch % _searchMatchCount + 1;
  });
  _scrollToSearchMatch();
}

void _previousSearchMatch() {
  if (_searchMatchIndices.isEmpty) return;
  setState(() {
    _currentSearchMatch = _currentSearchMatch <= 1
        ? _searchMatchCount
        : _currentSearchMatch - 1;
  });
  _scrollToSearchMatch();
}

void _scrollToSearchMatch() {
  if (_searchMatchIndices.isEmpty || _currentSearchMatch == 0) return;
  final index = _searchMatchIndices[_currentSearchMatch - 1];
  _scrollController.animateTo(
    index * 100.0, // Approximate item height
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
  );
}
```

- [ ] **Step 3: Add search toggle to the app bar PopupMenuButton**

Find the `PopupMenuButton` in `_buildAppBar()` and add a new menu item:
```dart
PopupMenuItem(
  value: 'search',
  child: Row(
    children: [
      Icon(Icons.search, color: Colors.white70, size: 20),
      const SizedBox(width: 12),
      Text('Search in chat', style: TextStyle(color: Colors.white)),
    ],
  ),
),
```

In the `onSelected` handler, add:
```dart
case 'search':
  setState(() => _showSearch = true);
  break;
```

- [ ] **Step 4: Add the search bar to the build method**

In the `build()` method, wrap the `Column` in a `Stack` and add the search bar overlay:
```dart
Stack(
  children: [
    Column(
      // ... existing column code
    ),
    if (_showSearch)
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: InChatSearchBar(
          onSearch: _filterMessages,
          onClose: () => setState(() => _showSearch = false),
          matchCount: _searchMatchCount,
          currentMatch: _currentSearchMatch,
          onNext: _nextSearchMatch,
          onPrevious: _previousSearchMatch,
        ),
      ),
  ],
)
```

- [ ] **Step 5: Run analysis**

Run: `flutter analyze lib/screens/assistant_screen.dart`
Expected: No new errors

- [ ] **Step 6: Commit**

```bash
git add lib/screens/assistant_screen.dart
git commit -m "feat: integrate in-chat message search with match navigation"
```

---

## Feature 5: Model Storage Breakdown in Settings

**Goal:** Show per-model storage usage in settings.

### Task 6: Add storage breakdown to settings

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/services/model_manager.dart` (if needed)

**Interfaces:**
- Consumes: `ModelManager.getStorageInfo()`
- Produces: List of models with size in MB

- [ ] **Step 1: Check how model storage is already exposed**

Look at `model_manager.dart` for existing storage info methods. The `getStorageInfo()` method should return tracked models with `fileSizeBytes`.

- [ ] **Step 2: Add a storage breakdown section to settings**

In the models hub (`_modelsHubChildren()`), add after existing tiles:
```dart
_sectionHeader('STORAGE BREAKDOWN'),
// FutureBuilder to load storage info
FutureBuilder<Map<String, dynamic>>(
  future: _loadStorageBreakdown(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final breakdown = snapshot.data!;
    final models = breakdown['models'] as List<Map<String, dynamic>>?;
    if (models == null || models.isEmpty) {
      return _infoTile(
        icon: Icons.storage_outlined,
        title: 'No models installed',
      );
    }
    return Column(
      children: models.map((m) => _infoTile(
        icon: Icons.memory,
        title: m['name'] ?? 'Unknown',
        subtitle: '${m['sizeMB']?.toStringAsFixed(1) ?? '?'} MB',
      )).toList(),
    );
  },
),
```

- [ ] **Step 3: Add the storage loading method**

```dart
Future<Map<String, dynamic>> _loadStorageBreakdown() async {
  final models = await ModelManager.instance.getInstalledModels();
  final List<Map<String, dynamic>> modelList = [];
  for (final model in models) {
    modelList.add({
      'name': model.displayName,
      'sizeMB': model.fileSizeBytes / (1024 * 1024),
      'path': model.filePath,
    });
  }
  final totalMB = modelList.fold<double>(0, (sum, m) => sum + (m['sizeMB'] as double));
  return {
    'models': modelList,
    'totalMB': totalMB,
  };
}
```

- [ ] **Step 4: Run analysis**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: No new errors

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: add model storage breakdown in settings"
```

---

## Feature 6: Chat Bubble Themes

**Goal:** Add customizable bubble color themes (default, ocean, forest, neon).

### Task 7: Create the bubble theme model

**Files:**
- Create: `lib/models/chat_bubble_theme.dart`

**Interfaces:**
- Consumes: Nothing (standalone model)
- Produces: `ChatBubbleTheme` class with color definitions

- [ ] **Step 1: Create the theme model**

```dart
// lib/models/chat_bubble_theme.dart
import 'package:flutter/material.dart';

enum ChatBubbleThemeType { defaultTheme, ocean, forest, neon, custom }

class ChatBubbleTheme {
  const ChatBubbleTheme({
    required this.name,
    required this.type,
    required this.userBubbleColor,
    required this.assistantBubbleColor,
    required this.backgroundColor,
    required this.userTextColor,
    required this.assistantTextColor,
    required this.accentColor,
  });

  final String name;
  final ChatBubbleThemeType type;
  final Color userBubbleColor;
  final Color assistantBubbleColor;
  final Color backgroundColor;
  final Color userTextColor;
  final Color assistantTextColor;
  final Color accentColor;

  static const defaultTheme = ChatBubbleTheme(
    name: 'Default',
    type: ChatBubbleThemeType.defaultTheme,
    userBubbleColor: Color(0xFF6C63FF),
    assistantBubbleColor: Color(0xFF1A1A2E),
    backgroundColor: Color(0xFF0D0D1A),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF6C63FF),
  );

  static const ocean = ChatBubbleTheme(
    name: 'Ocean',
    type: ChatBubbleThemeType.ocean,
    userBubbleColor: Color(0xFF0077B6),
    assistantBubbleColor: Color(0xFF023E8A),
    backgroundColor: Color(0xFF03045E),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF00B4D8),
  );

  static const forest = ChatBubbleTheme(
    name: 'Forest',
    type: ChatBubbleThemeType.forest,
    userBubbleColor: Color(0xFF2D6A4F),
    assistantBubbleColor: Color(0xFF1B4332),
    backgroundColor: Color(0xFF081C15),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF52B788),
  );

  static const neon = ChatBubbleTheme(
    name: 'Neon',
    type: ChatBubbleThemeType.neon,
    userBubbleColor: Color(0xFFFF006E),
    assistantBubbleColor: Color(0xFF1A1A2E),
    backgroundColor: Color(0xFF0D0D1A),
    userTextColor: Colors.white,
    assistantTextColor: Color(0xEBFFFFFF),
    accentColor: Color(0xFF8338EC),
  );

  static const values = [defaultTheme, ocean, forest, neon];

  static ChatBubbleTheme fromType(ChatBubbleThemeType type) {
    return values.firstWhere(
      (t) => t.type == type,
      orElse: () => defaultTheme,
    );
  }

  ChatBubbleThemeType typeFromName(String name) {
    return ChatBubbleThemeType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ChatBubbleThemeType.defaultTheme,
    );
  }
}
```

- [ ] **Step 2: Run analysis on the new model**

Run: `flutter analyze lib/models/chat_bubble_theme.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/models/chat_bubble_theme.dart
git commit -m "feat: add ChatBubbleTheme model with ocean, forest, and neon themes"
```

---

### Task 8: Create the bubble theme provider

**Files:**
- Create: `lib/utils/bubble_theme_provider.dart`

**Interfaces:**
- Consumes: `SharedPreferences` key `settings_bubble_theme`
- Produces: Current `ChatBubbleTheme`

- [ ] **Step 1: Create the theme provider**

```dart
// lib/utils/bubble_theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_assistant/models/chat_bubble_theme.dart';

class BubbleThemeProvider extends ChangeNotifier {
  BubbleThemeProvider() {
    _loadTheme();
  }

  static const String _prefsKey = 'settings_bubble_theme';
  ChatBubbleTheme _currentTheme = ChatBubbleTheme.defaultTheme;

  ChatBubbleTheme get currentTheme => _currentTheme;

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_prefsKey) ?? 'defaultTheme';
    final type = ChatBubbleThemeType.values.firstWhere(
      (t) => t.name == themeName,
      orElse: () => ChatBubbleThemeType.defaultTheme,
    );
    _currentTheme = ChatBubbleTheme.fromType(type);
    notifyListeners();
  }

  Future<void> setTheme(ChatBubbleThemeType type) async {
    _currentTheme = ChatBubbleTheme.fromType(type);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, type.name);
    notifyListeners();
  }
}
```

- [ ] **Step 2: Run analysis**

Run: `flutter analyze lib/utils/bubble_theme_provider.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/utils/bubble_theme_provider.dart
git commit -m "feat: add BubbleThemeProvider for persistent theme selection"
```

---

### Task 9: Integrate bubble themes into chat_bubble.dart

**Files:**
- Modify: `lib/widgets/chat_bubble.dart`

**Interfaces:**
- Consumes: `ChatBubbleTheme` from provider
- Produces: Themed bubble rendering

- [ ] **Step 1: Import the theme provider and add it to the widget**

```dart
import 'package:nova_assistant/models/chat_bubble_theme.dart';
```

Add a `theme` parameter to `ChatBubble`:
```dart
const ChatBubble({
  super.key,
  required this.message,
  required this.isLast,
  // ... existing params
  this.theme,
});

final ChatBubbleTheme? theme;
```

- [ ] **Step 2: Replace hardcoded colors with theme colors**

Replace the hardcoded color constants with theme-aware values:

```dart
// Before:
// Color(0xFF6C63FF) for user bubble
// Color(0xFF1A1A2E) for assistant bubble

// After:
final effectiveTheme = theme ?? ChatBubbleTheme.defaultTheme;
final userBubbleColor = effectiveTheme.userBubbleColor;
final assistantBubbleColor = effectiveTheme.assistantBubbleColor;
```

- [ ] **Step 3: Run analysis**

Run: `flutter analyze lib/widgets/chat_bubble.dart`
Expected: No new errors

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/chat_bubble.dart
git commit -m "feat: integrate ChatBubbleTheme into ChatBubble widget"
```

---

### Task 10: Add theme picker to settings_screen.dart

**Files:**
- Modify: `lib/screens/settings_screen.dart`

**Interfaces:**
- Consumes: `BubbleThemeProvider`
- Produces: Theme selection UI

- [ ] **Step 1: Add theme picker to appearance hub**

In `_appearanceHubChildren()`, add:
```dart
_sectionHeader('CHAT BUBBLE THEME'),
...ChatBubbleTheme.values.map((theme) => RadioListTile<ChatBubbleThemeType>(
  title: Text(theme.name, style: const TextStyle(color: Colors.white)),
  subtitle: Container(
    height: 24,
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      gradient: LinearGradient(
        colors: [theme.userBubbleColor, theme.assistantBubbleColor],
      ),
    ),
  ),
  value: theme.type,
  groupValue: _selectedBubbleTheme,
  activeColor: theme.accentColor,
  onChanged: (type) {
    if (type == null) return;
    setState(() => _selectedBubbleTheme = type);
    _saveBubbleTheme(type);
  },
)),
```

- [ ] **Step 2: Add state and loading logic**

```dart
ChatBubbleThemeType _selectedBubbleTheme = ChatBubbleThemeType.defaultTheme;

// In _loadSettings():
final themeName = prefs.getString('settings_bubble_theme') ?? 'defaultTheme';
_selectedBubbleTheme = ChatBubbleThemeType.values.firstWhere(
  (t) => t.name == themeName,
  orElse: () => ChatBubbleThemeType.defaultTheme,
);

Future<void> _saveBubbleTheme(ChatBubbleThemeType type) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('settings_bubble_theme', type.name);
}
```

- [ ] **Step 3: Run analysis**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: No new errors

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: add chat bubble theme picker in settings"
```

---

### Task 11: Wire theme into assistant_screen.dart

**Files:**
- Modify: `lib/screens/assistant_screen.dart`

**Interfaces:**
- Consumes: `BubbleThemeProvider`
- Produces: Themed chat background and bubbles

- [ ] **Step 1: Add theme state and load it**

```dart
import 'package:nova_assistant/models/chat_bubble_theme.dart';

// In _AssistantScreenState:
ChatBubbleTheme _chatTheme = ChatBubbleTheme.defaultTheme;

// In _loadSettings():
final themeName = prefs.getString('settings_bubble_theme') ?? 'defaultTheme';
final type = ChatBubbleThemeType.values.firstWhere(
  (t) => t.name == themeName,
  orElse: () => ChatBubbleThemeType.defaultTheme,
);
_chatTheme = ChatBubbleTheme.fromType(type);
```

- [ ] **Step 2: Apply theme background color**

Replace the hardcoded `Color(0xFF0D0D1A)` scaffold background:
```dart
// Before:
backgroundColor: const Color(0xFF0D0D1A),

// After:
backgroundColor: _chatTheme.backgroundColor,
```

- [ ] **Step 3: Pass theme to ChatBubble widgets**

In the `ListView.builder`, pass the theme to each `ChatBubble`:
```dart
ChatBubble(
  message: msg,
  isLast: isLast,
  theme: _chatTheme,
  // ... other params
)
```

- [ ] **Step 4: Run analysis**

Run: `flutter analyze lib/screens/assistant_screen.dart`
Expected: No new errors

- [ ] **Step 5: Commit**

```bash
git add lib/screens/assistant_screen.dart
git commit -m "feat: wire ChatBubbleTheme into assistant screen"
```

---

## Feature 7: Battery-Aware Model Switching

**Goal:** Auto-downgrade to lighter model when battery is below 20%.

### Task 12: Add battery level monitoring

**Files:**
- Modify: `lib/services/platform_adaptation_service.dart`
- Modify: `android/app/src/main/kotlin/dev/nova/assistant/MainActivity.kt` (if needed)

**Interfaces:**
- Consumes: Android BatteryManager via MethodChannel
- Produces: Battery level stream

- [ ] **Step 1: Check if battery level is already accessible**

Search for `BatteryManager` or `battery` in the Kotlin code. If not present, add a method channel call.

- [ ] **Step 2: Add battery level method to platform adaptation service**

```dart
// In platform_adaptation_service.dart:
static const _batteryChannel = MethodChannel('dev.nova.assistant/battery');

Future<int> getBatteryLevel() async {
  try {
    final level = await _batteryChannel.invokeMethod<int>('getBatteryLevel');
    return level ?? 100;
  } catch (e) {
    return 100; // Default to full if unavailable
  }
}
```

- [ ] **Step 3: Add battery level handler in MainActivity.kt**

```kotlin
// In MainActivity.kt, in configureFlutterEngine:
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.nova.assistant/battery").setMethodCallHandler { call, result ->
    if (call.method == "getBatteryLevel") {
        val batteryLevel = getBatteryLevel()
        result.success(batteryLevel)
    } else {
        result.notImplemented()
    }
}

private fun getBatteryLevel(): Int {
    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
    return batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
}
```

- [ ] **Step 4: Run analysis**

Run: `flutter analyze lib/services/platform_adaptation_service.dart`
Expected: No new errors

- [ ] **Step 5: Commit**

```bash
git add lib/services/platform_adaptation_service.dart android/app/src/main/kotlin/dev/nova/assistant/MainActivity.kt
git commit -m "feat: add battery level monitoring via platform channel"
```

---

### Task 13: Implement battery-aware model switching

**Files:**
- Modify: `lib/services/model_orchestrator.dart`

**Interfaces:**
- Consumes: `PlatformAdaptationService.getBatteryLevel()`
- Produces: Automatic model downgrade on low battery

- [ ] **Step 1: Add battery-aware switching logic**

```dart
// In model_orchestrator.dart:
bool _batteryAwareSwitching = true;
static const _lowBatteryThreshold = 20;

void setBatteryAwareSwitching(bool enabled) {
  _batteryAwareSwitching = enabled;
}

Future<void> checkBatteryAndSwitch() async {
  if (!_batteryAwareSwitching) return;
  if (_isStreaming || _isLoadingModel) return;

  final batteryLevel = await PlatformAdaptationService.instance.getBatteryLevel();
  if (batteryLevel <= _lowBatteryThreshold) {
    final currentModel = _activeModelType;
    if (currentModel == NovaModel.gemma4_e2b || currentModel == NovaModel.gemma4_e2b_thinking) {
      // Downgrade to lighter model
      final fallback = await _pickRamFallback(currentModel!);
      if (fallback != null) {
        _statusController.add('Low battery ($batteryLevel%) — switching to ${fallback.displayName}');
        // Store the original model for potential restore
        _previousModelBeforeBattery = currentModel;
        // Trigger model switch
        await switchModel(fallback);
      }
    }
  } else if (_previousModelBeforeBattery != null && batteryLevel > _lowBatteryThreshold + 10) {
    // Restore original model when battery recovers (with hysteresis)
    _statusController.add('Battery recovered ($batteryLevel%) — restoring ${_previousModelBeforeBattery!.displayName}');
    await switchModel(_previousModelBeforeBattery!);
    _previousModelBeforeBattery = null;
  }
}

NovaModel? _previousModelBeforeBattery;
```

- [ ] **Step 2: Add periodic battery check**

In the idle timer reset or a separate timer:
```dart
Timer? _batteryCheckTimer;

void _startBatteryCheck() {
  _batteryCheckTimer?.cancel();
  _batteryCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
    checkBatteryAndSwitch();
  });
}

void _stopBatteryCheck() {
  _batteryCheckTimer?.cancel();
  _batteryCheckTimer = null;
}
```

Start the battery check when the orchestrator initializes, stop it on dispose.

- [ ] **Step 3: Add setting toggle**

In settings_screen.dart, add:
```dart
_toggleTile(
  icon: Icons.battery_saver_outlined,
  title: 'Battery-aware model switching',
  subtitle: 'Switch to lighter model when battery is low',
  value: _batteryAwareSwitching,
  onChanged: (v) {
    setState(() => _batteryAwareSwitching = v);
    _saveSetting('settings_battery_aware_switching', v);
    ModelOrchestrator.instance.setBatteryAwareSwitching(v);
  },
),
```

- [ ] **Step 4: Run analysis**

Run: `flutter analyze lib/services/model_orchestrator.dart lib/screens/settings_screen.dart`
Expected: No new errors

- [ ] **Step 5: Commit**

```bash
git add lib/services/model_orchestrator.dart lib/screens/settings_screen.dart
git commit -m "feat: implement battery-aware model switching with auto-downgrade"
```

---

## Testing Tasks

### Task 14: Write tests for new features

**Files:**
- Create: `test/models/chat_bubble_theme_test.dart`
- Create: `test/utils/bubble_theme_provider_test.dart`
- Create: `test/widgets/in_chat_search_bar_test.dart`

**Interfaces:**
- Consumes: All new classes
- Produces: Unit tests

- [ ] **Step 1: Create theme model tests**

```dart
// test/models/chat_bubble_theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/models/chat_bubble_theme.dart';

void main() {
  group('ChatBubbleTheme', () {
    test('defaultTheme has correct colors', () {
      expect(ChatBubbleTheme.defaultTheme.userBubbleColor, const Color(0xFF6C63FF));
      expect(ChatBubbleTheme.defaultTheme.type, ChatBubbleThemeType.defaultTheme);
    });

    test('values contains all themes', () {
      expect(ChatBubbleTheme.values.length, 4);
    });

    test('fromType returns correct theme', () {
      final ocean = ChatBubbleTheme.fromType(ChatBubbleThemeType.ocean);
      expect(ocean.name, 'Ocean');
      expect(ocean.type, ChatBubbleThemeType.ocean);
    });

    test('fromType returns default for unknown type', () {
      // This tests the orElse fallback
      final theme = ChatBubbleTheme.fromType(ChatBubbleThemeType.custom);
      expect(theme.type, ChatBubbleThemeType.defaultTheme);
    });
  });
}
```

- [ ] **Step 2: Run theme tests**

Run: `flutter test test/models/chat_bubble_theme_test.dart`
Expected: All tests pass

- [ ] **Step 3: Create search bar widget test**

```dart
// test/widgets/in_chat_search_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_assistant/widgets/in_chat_search_bar.dart';

void main() {
  group('InChatSearchBar', () {
    testWidgets('renders search input', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InChatSearchBar(
            onSearch: (_) {},
            onClose: () {},
          ),
        ),
      ));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('shows match count', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InChatSearchBar(
            onSearch: (_) {},
            onClose: () {},
            matchCount: 5,
            currentMatch: 2,
          ),
        ),
      ));

      expect(find.text('2/5'), findsOneWidget);
    });

    testWidgets('shows navigation buttons when multiple matches', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InChatSearchBar(
            onSearch: (_) {},
            onClose: () {},
            matchCount: 3,
            currentMatch: 1,
            onNext: () {},
            onPrevious: () {},
          ),
        ),
      ));

      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });
  });
}
```

- [ ] **Step 4: Run search bar tests**

Run: `flutter test test/widgets/in_chat_search_bar_test.dart`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add test/models/chat_bubble_theme_test.dart test/widgets/in_chat_search_bar_test.dart
git commit -m "test: add unit and widget tests for new features"
```

---

## Final Verification

- [ ] **Step 1: Run full analysis**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 2: Run all tests**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 3: Run format check**

Run: `dart format --set-exit-if-changed .`
Expected: No formatting issues

- [ ] **Step 4: Final commit if needed**

```bash
git add -A
git commit -m "chore: format and finalize feature batch implementation"
```

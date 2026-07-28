# Task 1: Add attribution to copy action

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

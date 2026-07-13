# Task 3: Fix ParallelSessionManager CancelProcess Crash

## Goal

Apply the same streaming-state coordination fix that Task 1 applied to `ModelOrchestrator` to `ParallelSessionManager`, preventing a native crash when `closeSession()` or `releaseAllSessions()` calls `close()` while an active `generateChatResponseAsync()` stream is still iterating.

## Root Cause

Identical to ModelOrchestrator: `closeSession()` sets `_sessions[id]!.chat = null` but the `await for` loop in `sendMessage()` still holds a reference to the native stream. A subsequent `close()` call triggers `CancelProcess()` while the stream is active, crashing `libLiteRtLm.so`.

## Files to Modify

- `lib/services/parallel_session_manager.dart`

## Changes Required

### 1. Add streaming state fields (after line ~106, near `_sessions` field):

```dart
  final Map<String, bool> _isStreaming = {};
  final Map<String, Completer<void>?> _streamingCompleters = {};
```

### 2. Update `sendMessage()` (lines 159-199)

Before the `await for` loop, set streaming state:

```dart
      _isStreaming[sessionId] = true;
      _streamingCompleters[sessionId] = Completer<void>();
```

Inside the `await for` loop, check for abort:

```dart
      await for (final event in sessions[sessionId]!.chat!.generateChatResponseAsync()) {
        // Check if session close signaled abort
        if (_streamingCompleters[sessionId]?.isCompleted ?? false) {
          debugPrint('Session $sessionId stream aborted by close');
          break;
        }
```

After the loop, clear streaming state:

```dart
      _isStreaming[sessionId] = false;
      if (_streamingCompleters[sessionId] != null && !_streamingCompleters[sessionId]!.isCompleted) {
        _streamingCompleters[sessionId]!.complete();
      }
      _streamingCompleters.remove(sessionId);
```

### 3. Update `closeSession()` (lines 201-213)

Before clearing chat, signal abort and wait for stream to finish:

```dart
  Future<void> closeSession(String sessionId) async {
    final sessions = _sessions;
    if (sessions.containsKey(sessionId)) {
      // Signal any active stream to abort
      if (_streamingCompleters.containsKey(sessionId) && _streamingCompleters[sessionId] != null && !_streamingCompleters[sessionId]!.isCompleted) {
        _streamingCompleters[sessionId]!.complete();
      }

      // Clear the chat reference
      sessions[sessionId]!.chat = null;

      // Wait for any ongoing stream to finish (up to 3 seconds)
      if (_isStreaming[sessionId] == true) {
        debugPrint('Waiting for session $sessionId stream to finish...');
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (_isStreaming[sessionId] == true && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await sessions[sessionId]!.model.close();
      _sessions.remove(sessionId);
      _isStreaming.remove(sessionId);
      _streamingCompleters.remove(sessionId);
    }
  }
```

### 4. Update `releaseAllSessions()` (lines 220-232)

Add abort signal before closing each session:

```dart
  Future<void> releaseAllSessions() async {
    final sessions = _sessions;
    if (sessions.isNotEmpty) {
      for (final id in sessions.keys.toList()) {
        // Signal active stream to abort
        if (_streamingCompleters.containsKey(id) && _streamingCompleters[id] != null && !_streamingCompleters[id]!.isCompleted) {
          _streamingCompleters[id]!.complete();
        }
        sessions[id]!.chat = null;

        // Wait for any ongoing stream
        if (_isStreaming[id] == true) {
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (_isStreaming[id] == true && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }

        await sessions[id]!.model.close();
      }
      _sessions.clear();
      _isStreaming.clear();
      _streamingCompleters.clear();
    }
  }
```

## Acceptance Criteria

1. `_isStreaming[sessionId]` tracks whether a stream is active per session
2. `_streamingCompleters[sessionId]` signals abort when session is closed
3. `closeSession()` waits up to 3 seconds for any active stream to finish before calling `close()`
4. `releaseAllSessions()` signals abort and waits for all active streams
5. No native crash when closing a session while `sendMessage()` is actively streaming

## Key Implementation Notes

- Each session gets its own streaming state (per-session maps, not shared booleans)
- Follow existing error handling patterns in the file (try-catch around model.close())
- The 3-second timeout prevents infinite hanging if a stream gets stuck
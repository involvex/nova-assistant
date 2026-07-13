# Task 1: Fix LiteRtLm CancelProcess Crash in ModelOrchestrator

## Goal

Prevent `close()` from being called on a LiteRtLm model while `generateChatResponseAsync()` stream is actively iterating, which causes a native crash in `litert::lm::Conversation::CancelProcess()`.

## Root Cause

In `model_orchestrator.dart`, when `releaseIdleResources()` is called (due to app lifecycle or idle timeout):
1. `_activeChat = null` is set, but this does NOT abort the native stream
2. 100ms delay passes
3. `_activeModel!.close()` is called, triggering native `CancelProcess()`
4. The native stream is still iterating → CRASH

## Files to Modify

- `lib/services/model_orchestrator.dart`

## Changes Required

### 1. Add streaming state fields after line 133 (`_idleTimer` line):

```dart
  bool _isStreaming = false;
  Completer<void>? _streamingCompleter;
```

### 2. Update `preferredModelType` setter (lines 162-175)

After `_activeChat = null;` (line 166), add:
```dart
    // Signal any active stream to abort
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
```

### 3. Replace `_releaseIdleResources()` (lines 217-262)

New implementation must:
- Signal any active stream via `_streamingCompleter?.complete()`
- Wait for `_isStreaming` to become false before calling `close()`
- Use a timeout (3 seconds) for the wait
- Keep the existing `_isReleasing` guard

```dart
  Future<void> _releaseIdleResources() async {
    if (_isReleasing) {
      debugPrint('Release already in progress, skipping');
      return;
    }
    _isReleasing = true;

    try {
      if (!_batteryOptimizationEnabled) return;

      // Signal any active stream to abort
      if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
        _streamingCompleter!.complete();
      }

      // Clear the chat reference
      if (_activeChat != null) {
        try {
          _activeChat = null;
        } catch (_) {}
      }

      // Wait for any ongoing stream iteration to finish
      if (_isStreaming) {
        debugPrint('Waiting for active stream to finish...');
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (_isStreaming && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (_isStreaming) {
          debugPrint('Stream did not finish in time, forcing release');
        }
      }

      // Now close the model
      if (_activeModel != null) {
        try {
          await _activeModel!.close();
        } catch (e) {
          debugPrint('Error closing model: $e');
        }
      }
      _activeModel = null;
      _activeModelSupportsImage = false;

      _statusController.add('Idle — model released to save battery');
    } catch (e) {
      debugPrint('Error releasing idle resources: $e');
    } finally {
      _isReleasing = false;
    }
  }
```

### 4. Update `processMessage()` stream handling (lines 822-926)

The `await for` loop at line 826 must track streaming state:

Before the loop (around line 822):
```dart
    // Set streaming state for releaseIdleResources() to observe
    _isStreaming = true;
    _streamingCompleter = Completer<void>();

    try {
      await for (final event in _activeChat!.generateChatResponseAsync()) {
        // Check if releaseIdleResources() signaled abort
        if (_streamingCompleter?.isCompleted ?? false) {
          debugPrint('Stream aborted by releaseIdleResources');
          break;
        }
```

After the loop ends (wrap the entire while loop in try/finally):
```dart
      } // end await for
    } finally {
      // Clear streaming state
      _isStreaming = false;
      if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
        _streamingCompleter!.complete();
      }
      _streamingCompleter = null;
    }
```

### 5. Update `clearHistory()` (line 1166)

Add before `_activeChat = null`:
```dart
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
```

## Acceptance Criteria

1. `_isStreaming` flag is set to `true` before entering the `await for` loop and `false` in `finally`
2. `_streamingCompleter` signals abort to the loop when `releaseIdleResources()` is called
3. `close()` is NOT called while `_isStreaming == true` (waits up to 3 seconds)
4. The crash at `CancelProcess()` does not occur when app is backgrounded during inference

## Key Implementation Notes

- The `await for` loop in Dart does NOT automatically exit when `_activeChat` is set to null
- The `Completer` is the signaling mechanism — when `complete()` is called, the loop checks `isCompleted` and breaks
- The timeout prevents infinite waiting if the stream hangs
- Follow existing code patterns for `debugPrint` and error handling
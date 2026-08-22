# Performance Optimization Plan — Nova Assistant

## Scope
Fix 7 performance bottlenecks identified in the previous session:
1. ChatHistoryService incremental append
2. KnowledgeBaseService pre-tokenization
3. SemanticSearch content-hash cache validation
4. AssistantScreen build/widget split
5. ModelOrchestrator context budget hot-path unification
6. MemoryService read-on-mutation elimination
7. Debug log test coverage

---

## 1. ChatHistoryService — Incremental Append

**File:** `lib/services/chat_history_service.dart`

### Problem
Every mutation (`appendMessage`, `updateConversation`, `deleteConversation`, `createConversation`) loads the full JSON list from disk, mutates in memory, and rewrites the entire file. During active chat this means repeated full serialization even when only one message changed.

### Implementation
- Add a private `_appendJsonEntry(String entry)` method that opens the file in append mode and writes a single JSON object with a newline delimiter.
- Change `appendMessage()` to use `_appendJsonEntry()` instead of load-then-save-all.
- Keep `saveConversations()` as the compaction path: when `_maxMessagesPerConversation` or `_maxConversations` limits are hit, or after N append-only writes, rewrite the full file from the in-memory cache to enforce caps and sanitization.
- Add a `_appendCount` counter; when it reaches a threshold (e.g., 50), trigger compaction.
- Ensure `_sanitizeConversation()` and `_capConversations()` still run during compaction.

### Verification
- Run `flutter test test/services/chat_history_export_test.dart`
- Run `flutter test test/services/chat_history_branch_test.dart`
- Run `flutter analyze`

---

## 2. KnowledgeBaseService — Pre-Tokenization Cache

**File:** `lib/services/knowledge_base_service.dart`

### Problem
`retrieveContext()` re-tokenizes every chunk via `SemanticSearch.tokenize(e.chunk)` on every query. With large corpora this is CPU-heavy on the hot path.

### Implementation
- Add a `_cachedChunkTokens` map in `KnowledgeBaseService`: `Map<String, List<String>>` keyed by document ID + chunk index, or by a content hash of the chunk text.
- On `ingestFile()`, after chunking, pre-tokenize each chunk and store in `_cachedChunkTokens`.
- In `retrieveContext()`, look up cached tokens instead of calling `SemanticSearch.tokenize()` per chunk.
- Invalidate cache entries when documents are deleted or re-ingested.

### Verification
- Add unit test for `ingestFile` populating `_cachedChunkTokens`.
- Add unit test for `retrieveContext` using cached tokens.
- Run `flutter test test/services/semantic_search_test.dart`
- Run `flutter analyze`

---

## 3. SemanticSearch — Content-Hash Cache Validation

**File:** `lib/services/semantic_search.dart`

### Problem
`_corpusCache` validation in `search()` only checks document token count lengths (lines 190–213). If two corpora have the same token counts but different content, stale IDF values are reused incorrectly.

### Implementation
- Change `_CachedCorpus` to include a `contentHash` field computed from the concatenated tokens of each document.
- In `search()`, compare the new corpus hash against `_corpusCache!.contentHash` instead of per-document token counts.
- Compute hash with a simple deterministic function (e.g., join tokens, hash the string).
- If hash mismatches, recompute IDF and update cache.

### Verification
- Add unit test where corpus token counts match but content differs; verify cache miss.
- Run `flutter test test/services/semantic_search_test.dart`
- Run `flutter analyze`

---

## 4. AssistantScreen — Widget Split

**File:** `lib/screens/assistant_screen.dart`

### Problem
`AssistantScreen` is a ~3346-line monolithic StatefulWidget. The `build()` method returns a heavy `Scaffold` with a `Stack` containing many overlays and a `ListView.builder` of 200 messages. Every `setState` triggers the full build even though only the message list or input bar may need updating.

### Implementation
- Extract `_buildMessageList()` into a separate `StatelessWidget` (e.g., `MessageListView`) that takes `List<ChatMessage>`, `ThemeData`, and callback closures as constructor parameters.
- Extract `_buildInputBar()` into a separate `StatelessWidget` (e.g., `ChatInputBar`) with its own state for text editing and send actions, lifted via callbacks.
- Extract overlay widgets (`_buildOfflineBanner`, `_buildDebugBanner`, `_buildModelLoadingOverlay`) into their own `StatelessWidget`s.
- In the parent `AssistantScreen.build()`, compose these extracted widgets.
- Use `const` constructors where possible for extracted widgets.
- Consider wrapping `MessageListView` in an `AutomaticKeepAliveClientMixin` if it holds scroll state across tab switches.

### Verification
- Run `flutter analyze`
- Run full test suite `flutter test`

---

## 5. ModelOrchestrator — Context Budget Hot-Path Unification

**Files:**
- `lib/services/model_orchestrator.dart`
- `lib/screens/assistant_screen.dart`

### Problem
Token estimation is duplicated: `AssistantScreen._refreshLocalContextBudget()` estimates history tokens from `_messages`, while `ModelOrchestrator.processMessage()` estimates from `_activeChat!.fullHistory`. Both run synchronously on the UI thread. `_truncateContext()` also uses a legacy `(text.length / 4).round()` heuristic instead of the newer `_estimateRealTokens`.

### Implementation
- Remove `_refreshLocalContextBudget()` from the hot path in `AssistantScreen`. Instead, subscribe to the existing `_contextNearLimitController` stream and update UI state reactively.
- In `ModelOrchestrator.processMessage()`, unify token estimation into a single `_computeContextBudget()` method that returns both the estimate and a boolean overflow flag, replacing the current multi-pass logic.
- Replace the legacy heuristic in `_truncateContext()` with `_estimateRealTokens` for consistency.
- Ensure `_autoCompactForBudget()` is only called after the unified estimate, not from multiple code paths.

### Verification
- Run `flutter test test/services/model_orchestrator_budget_test.dart`
- Run `flutter analyze`

---

## 6. MemoryService — Eliminate Read-on-Mutation

**File:** `lib/services/memory_service.dart`

### Problem
Every mutation (`storeConversation`, `addCustomMemory`, `deleteCustomMemory`, `updateCustomMemory`) calls `_loadFromDisk()` first, even when the in-memory cache is already populated. This means each write does a full file read + full file write.

### Implementation
- Add a `_cacheLoaded` flag. Set it to `true` after the first successful `_loadFromDisk()`.
- In mutation methods, check `_cacheLoaded` before calling `_loadFromDisk()`. If the cache is already loaded, skip the read and modify the in-memory structures directly.
- Only reload from disk if `_cacheLoaded` is false or after a crash recovery scenario.
- Keep `_scheduleWrite()` / `_flushToDisk()` debouncing intact.
- Ensure token caches (`_cachedConversationTokens`, `_cachedCustomMemoryTokens`) are invalidated correctly on mutations.

### Verification
- Add unit test verifying mutation methods skip disk read when cache is loaded.
- Run `flutter test test/services/user_memory_service_test.dart`
- Run `flutter analyze`

---

## 7. ModelOrchestrator Debug Log Test Coverage

**Files:**
- `lib/services/model_orchestrator.dart`
- `test/services/model_orchestrator_test.dart`

### Problem
No tests exist for `_debugLog()` gating behavior, `_debugMode` state transitions, or the `unawaited` fire-and-forget pattern. Two direct `AgentDebugLog.log()` calls also bypass the `_debugLog()` helper.

### Implementation
- Add `testDebugLog()` group to `model_orchestrator_test.dart`:
  - Test that `_debugLog()` does nothing when `_debugMode` is false.
  - Test that `_debugLog()` calls `AgentDebugLog.log` when `_debugMode` is true.
  - Test `setDebugMode(true/false)` state transitions.
- Migrate the two remaining direct `AgentDebugLog.log(...)` calls (lines 1473–1487, 2857–2871) to use `_debugLog()` for consistency.
- Verify no other direct `AgentDebugLog.log()` calls exist outside `_debugLog()`.

### Verification
- Run `flutter test test/services/model_orchestrator_test.dart`
- Run `flutter analyze`

---

## Cross-Cutting Verification

After all changes:
```bash
flutter analyze
flutter test
```

All existing tests must pass. If any new tests are added, they must also pass.

---

## Execution Order

1. SemanticSearch content-hash cache (isolated, low risk)
2. KnowledgeBaseService pre-tokenization (depends on SemanticSearch tokenize contract)
3. MemoryService read-on-mutation elimination (isolated)
4. ChatHistoryService incremental append (medium risk, affects persistence)
5. ModelOrchestrator context budget unification (medium risk, affects inference flow)
6. Debug log test coverage (isolated, add tests alongside changes)
7. AssistantScreen widget split (larger refactor, do last)

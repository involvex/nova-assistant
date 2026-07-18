# LAN Remote Inference (Host / Client Streaming) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one device on the local network **host** an inference endpoint and another Nova client **stream** completions from it — similar to “local dream” style LAN model sharing. This is also the supported way to use **large / GGUF** models without fighting LiteRtLm native conflicts on the phone.

**Architecture:** OpenAI-compatible HTTP API over LAN (`POST /v1/chat/completions` with `stream: true`).  
- **Host mode (v1):** Nova acts as a thin discovery + settings UI that points at an external host (llama.cpp server, Ollama, LM Studio, or a future Nova-native host). Optional Phase 2: embed a Dart `HttpServer` proxy only if a local engine can serve tokens.  
- **Client mode:** New `RemoteInferenceClient` + orchestrator branch when `settings_inference_backend == remote`. SSE/chunk streaming mapped to existing `InferenceResult` stream.  
- **Discovery:** Optional mDNS (`_nova-llm._tcp`) or manual `http://192.168.x.x:11434`.

**Tech Stack:** `dart:io` HttpClient (mobile/desktop), existing MCP HTTP patterns as reference (`lib/services/mcp_client.dart`), Settings screens, no new cloud deps.

## Global Constraints

- Bind host to LAN / localhost only — never expose without user action; show warning about untrusted Wi‑Fi.
- Auth: optional shared bearer token stored in prefs (not committed).
- On-device LiteRT remains default backend.
- Do **not** claim screen-monitor icons are LAN streaming — those stay MediaProjection screenshots.
- YAGNI: v1 is **client to existing OpenAI-compatible LAN server**. Native-in-app host process is Phase 2.

## File map

| File | Responsibility |
|------|----------------|
| `lib/models/inference_backend.dart` | Enum `onDevice` / `remote` + prefs |
| `lib/services/remote_inference_client.dart` | Chat completions streaming client |
| `lib/services/remote_inference_config.dart` | Base URL, model id, token |
| `lib/services/model_orchestrator.dart` | Branch `processMessage` to remote |
| `lib/screens/remote_inference_settings_screen.dart` | Configure host |
| `lib/screens/settings_screen.dart` | Entry + backend picker |
| `test/services/remote_inference_client_test.dart` | Parse SSE / JSON chunks with fake Http |

---

### Task 1: Config model + prefs (TDD)

**Files:**
- Create: `lib/models/inference_backend.dart`
- Create: `lib/services/remote_inference_config.dart`
- Test: `test/services/remote_inference_config_test.dart`

**Interfaces:**

```dart
enum InferenceBackend { onDevice, remote }

class RemoteInferenceConfig {
  const RemoteInferenceConfig({
    required this.baseUrl,
    required this.modelId,
    this.apiToken,
  });

  final String baseUrl; // e.g. http://192.168.1.20:8080
  final String modelId;
  final String? apiToken;

  static const backendPrefsKey = 'settings_inference_backend';
  static const baseUrlPrefsKey = 'settings_remote_base_url';
  static const modelIdPrefsKey = 'settings_remote_model_id';
  static const tokenPrefsKey = 'settings_remote_api_token';

  Uri chatCompletionsUri() =>
      Uri.parse(baseUrl.replaceAll(RegExp(r'/$'), '') + '/v1/chat/completions');

  Map<String, String> headers() => {
        'Content-Type': 'application/json',
        if (apiToken != null && apiToken!.isNotEmpty)
          'Authorization': 'Bearer $apiToken',
      };

  factory RemoteInferenceConfig.fromPrefs(SharedPreferences prefs) { ... }
  Future<void> save(SharedPreferences prefs) async { ... }
}
```

- [ ] **Step 1: Failing tests for URI + headers**
- [ ] **Step 2: Implement**
- [ ] **Step 3: Commit** `feat: remote inference config and backend enum`

---

### Task 2: Streaming client (TDD)

**Files:**
- Create: `lib/services/remote_inference_client.dart`
- Test: `test/services/remote_inference_client_test.dart`

**Interfaces:**

```dart
class RemoteInferenceClient {
  RemoteInferenceClient({HttpClient? httpClient});

  /// Yields text deltas from OpenAI-style SSE (`data: {...}`) or NDJSON.
  Stream<String> streamChat({
    required RemoteInferenceConfig config,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
  });
}
```

Request body:

```json
{
  "model": "<modelId>",
  "stream": true,
  "messages": [{"role":"system","content":"..."},{"role":"user","content":"..."}]
}
```

Parse:
- Lines starting with `data: ` → JSON `choices[0].delta.content`
- Terminate on `data: [DONE]`

Test with a `Stream<List<int>>` fixture (inject via custom `HttpClient` mock or extract `parseSseChunk(String line) → String?` pure function).

- [ ] **Step 1: Test pure SSE parser**

```dart
test('parses delta content', () {
  expect(
    RemoteInferenceClient.parseSseData(
      'data: {"choices":[{"delta":{"content":"Hi"}}]}',
    ),
    'Hi',
  );
  expect(RemoteInferenceClient.parseSseData('data: [DONE]'), isNull);
});
```

- [ ] **Step 2: Implement parser + streamChat**
- [ ] **Step 3: Commit** `feat: OpenAI-compatible LAN streaming client`

---

### Task 3: Orchestrator remote branch

**Files:**
- Modify: `lib/services/model_orchestrator.dart`

**Interfaces:**
- On `processMessage`, if backend is remote:

```dart
if (_inferenceBackend == InferenceBackend.remote) {
  yield* _processRemoteMessage(
    query: query,
    ragContext: ragContext,
    attachmentContext: attachmentContext,
  );
  return;
}
```

`_processRemoteMessage`:
1. Build system prompt via `_systemPromptFor` (no LiteRT tools in v1 — yield a one-time status if tools requested: “Tools unavailable on remote backend”).
2. Build messages list from pending replay + current user query (roles user/assistant).
3. `await for (final delta in RemoteInferenceClient().streamChat(...))` yield `InferenceResult(text: accumulated, isStreaming: true)`.
4. Final yield `isStreaming: false`.
5. Do **not** call `releaseIdleResources` for remote (nothing loaded).

Skip model download / GPU compile path entirely when remote.

- [ ] **Step 1: Implement branch**
- [ ] **Step 2: Manual test against Ollama**

```bash
# On host PC
ollama serve
# pull any model; note LAN IP
```

Point Nova client at `http://<lan-ip>:11434` model `llama3.2` (or whatever OpenAI-compat path Ollama exposes — if `/api/chat` only, document adapter or require llama.cpp `--server` OpenAI mode).

Prefer documenting **llama.cpp** `llama-server` OpenAI API for v1 to avoid dual protocols.

- [ ] **Step 3: Commit** `feat: orchestrator remote inference backend`

---

### Task 4: Settings UI

**Files:**
- Create: `lib/screens/remote_inference_settings_screen.dart`
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/services/settings_backup_service.dart`

**UI fields:**
- Backend: SegmentedButton On-device | Remote LAN
- Base URL text field
- Model id text field
- Optional token
- “Test connection” button → `GET /v1/models` or short non-stream completion
- Warning banner: “Only use on trusted private Wi‑Fi”

- [ ] **Step 1: Build screen**
- [ ] **Step 2: Link from Settings → AI Models / Advanced**
- [ ] **Step 3: Backup remote config (token included only if user exports — document risk)**
- [ ] **Step 4: Commit** `feat: remote LAN inference settings screen`

---

### Task 5: Docs + host cookbook

**Files:**
- Create: `docs/remote-inference.md`
- Modify: `docs/index.md` (link)
- Modify: `doc/PLAN-features.md`

Content must include:
1. How to run `llama-server -m model.gguf --host 0.0.0.0 --port 8080`
2. How to point Nova at it
3. That this is how GGUF / large models work today without on-device GGUF
4. Security notes (token, firewall, no public internet)

- [ ] **Step 1: Write docs**
- [ ] **Step 2: Commit** `docs: remote LAN inference guide`

---

### Phase 2 (out of scope for this plan’s merge — track only)

- In-app host using a separate process / isolate with llama.cpp binaries.
- mDNS discovery UI.
- Tool-calling bridge over remote (OpenAI tools → local `ToolExecutorService`).
- Auth pairing QR code.

Do not implement Phase 2 in the same PR as Tasks 1–5.

---

## Self-review

1. Covers “one device hosts and streams across local network”.
2. Practical path for large + GGUF models via host.
3. Does not conflict with LiteRtLm native libs.
4. Explicit non-goal preserved: no FGS warm host for on-device LiteRT.

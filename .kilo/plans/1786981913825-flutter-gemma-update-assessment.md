# flutter_gemma Update Assessment

## Current State

| Package | pubspec constraint | Resolved (lock) | Latest |
|---------|-------------------|-----------------|--------|
| `flutter_gemma` | `^1.5.0` | **1.5.2** | **1.5.9** |
| `flutter_gemma_litertlm` | `^1.0.2` | **1.3.1** | **1.4.2** |
| `flutter_gemma_mediapipe` | `^1.0.3` | **1.0.4** | 1.0.4 |
| `flutter_gemma_speech` | `^0.4.1` | **0.4.1** | **0.4.3** |

## Relevant Changes (1.5.2 → 1.5.9)

### flutter_gemma
- **1.5.9**: `getActiveModel(preferredVisionBackend:, preferredAudioBackend:)` — per-encoder backend override. Backward compatible.
- **1.5.7**: Fix `getInstalledModels(stt/tts/embedding)` returning inference models instead. Relevant if Nova lists installed STT/embedding models.
- **1.5.6**: Fix Gemma 4 streaming leaking raw tool-call JSON into the text channel. Relevant because Nova has a custom tool-call loop.
- **1.5.4**: Fix balance of committed tool-calls when generation stream errors mid-turn.
- **1.5.3**: `InferenceChat.generateChatResponseWithTools` added (new reusable function-calling driver). Nova does **not** use this — it has its own `_tryParseFunctionCalls` + `FunctionCallResponse` loop in `model_orchestrator.dart`.
- **1.5.1**: Namespace companion install files per model, fixing STT/embedding tokenizer collisions.

### flutter_gemma_litertlm
- **1.4.2**: Fix vision + audio encoders defaulting to CPU (overridable). Fixes GPU vision hard-fail on Metal/WebGPU.
- **1.4.1**: Fix Windows NPU OpenVino compiler DLLs not bundled.
- **1.4.0**: Migrate to LiteRT-LM v0.16.0. Fix Android OpenCL per-turn memory leak (#348, #402). Fix Windows discrete GPU. Rebuild NPU dispatch stacks. **Native library changes — higher risk.**

### flutter_gemma_speech
- **0.4.2**: Inflect-Nano-v2 TTS (fast on-device, English-only). `VoiceSession.fromChat` gains `onToolCall` for voice-loop function calling.
- **0.4.3**: `VoiceSession(streamAudio:)` for clause-by-clause TTS overlap with LLM stream.

## Impact Assessment

### What benefits Nova
1. **Android stability**: OpenCL per-turn leak fix (litertlm 1.4.0) directly affects Android GPU inference.
2. **Windows GPU**: Discrete GPU fix (litertlm 1.4.0) matters for Windows desktop users.
3. **Tool-call reliability**: 1.5.4/1.5.6 fixes improve the underlying engine that Nova’s custom tool loop depends on.
4. **Vision/audio backend control**: 1.5.9 + litertlm 1.4.2 allow per-encoder backend selection, useful for performance tuning.

### What does NOT benefit Nova directly
- `generateChatResponseWithTools` (1.5.3) — Nova uses its own tool loop.
- Voice-loop TTS features (speech 0.4.2+) — Nova uses a separate `tts_service.dart`, not `VoiceSession`.

### Risks
- **Native asset churn**: litertlm 1.4.0 bumps LiteRT-LM to v0.16.0 with rebuilt native libraries. May require clean rebuilds.
- **Fast cadence**: 7 releases in ~2 weeks. Updating now likely means another update within weeks.
- **No breaking changes in used APIs**: `createChat`, `generateChatResponseAsync`, `addQuery`, `getActiveModel` all remain backward compatible.

## Recommendation

**Worth updating, but not urgent.** The Android memory leak and Windows GPU fixes in `litertlm 1.4.0` are the strongest motivators. The tool-call streaming fixes (1.5.4, 1.5.6) improve reliability of the engine Nova depends on.

**If updating:**
1. Bump all `flutter_gemma*` packages together to avoid version skew.
2. Run `flutter clean` then rebuild to pick up native library changes.
3. Test tool calling on Android + Windows first (highest-risk platforms for native changes).
4. Expect another update cycle soon given the ~weekly release cadence.

## Proposed pubspec changes

```yaml
flutter_gemma: ^1.5.9
flutter_gemma_litertlm: ^1.4.2
flutter_gemma_mediapipe: ^1.0.4  # no change needed
flutter_gemma_speech: ^0.4.3
```

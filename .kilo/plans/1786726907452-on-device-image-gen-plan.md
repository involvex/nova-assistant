# Plan: On-Device Image Generation via LiteRT Diffusion

> Implementation plan for adding on-device text-to-image generation using a LiteRT
> multi-graph diffusion pipeline (Z-Image-Turbo or FLUX distilled) on the POCO X8 Pro Max.
> This is a P2 feature — medium impact, higher effort. It requires a new native inference
> path alongside the existing flutter_gemma LLM/VLM stack.

---

## Decision Record

**Chosen approach:** On-device diffusion via a separate native LiteRT pipeline.
- No external APIs, no MCP delegation, no LAN server required.
- Privacy-first: all inference runs on-device.
- Requires new Kotlin/C++ native code (not just Flutter-side changes).
- Candidate model: Z-Image-Turbo-LiteRT (smaller, faster) or FLUX.2-klein-4B-LiteRT (higher quality, larger).

---

## Critical Technical Reality Check

The existing `flutter_gemma` plugin ONLY handles LLM/VLM chat models (`.litertlm` / `.task`).
Diffusion models (Z-Image-Turbo, FLUX) are LiteRT `CompiledModel` multi-graph pipelines
(many `.tflite` chunks + host tokenizer/scheduler). They cannot be loaded through
`flutter_gemma`'s API. A **separate native inference path** is required.

This is not a "add a model file" change. It is a new Kotlin service + TFLite/LiteRT
dependency + tokenizer/scheduler implementation.

---

## Phase 0: Feasibility Verification (Do First — Gate)

Before any production code, verify on the POCO X8 Pro Max:

1. **NNAPI availability:**
   - `adb shell dumpsys SurfaceFlinger | grep -i gpu` → confirm PowerVR GPU
   - `adb shell getprop ro.hardware.chipname` → confirm MediaTek Dimensity 8400
   - Test: minimal LiteRT CompiledModel loading via throwaway Android test app

2. **LiteRT multi-graph API:**
   - Verify `LiteRtCompiledModel` supports multi-graph execution on Android
   - Check if Z-Image-Turbo-LiteRT or FLUX.2-klein-4B-LiteRT have published Android inference examples
   - If LiteRT's CompiledModel API is not public/stable, this feature is blocked

3. **Memory budget:**
   - Android system + Nova LLM stack: ~4-6GB on 12GB device
   - Z-Image-Turbo: ~800MB download, ~2GB RAM during inference
   - FLUX.2-klein: ~2GB download, ~4GB+ RAM during inference
   - Realistic free RAM after LLM stack: ~6GB → Z-Image-Turbo fits, FLUX risky

**Go/No-go:** If LiteRT multi-graph fails on device, stop. Do not proceed to Phase 1.

---

## Phase 1: Native Diffusion Service (Kotlin)

**New files:**
- `android/app/src/main/kotlin/dev/nova/assistant/ImageGenerationService.kt`
- `android/app/src/main/kotlin/dev/nova/assistant/ImageGenerationModels.kt`

**What ImageGenerationService.kt does:**
1. Loads a LiteRT `CompiledModel` from `.tflite` files in app documents directory
2. Runs inference with NNAPI delegate (GPU preferred, CPU fallback)
3. Accepts text prompt + size/seed parameters via MethodChannel
4. Returns generated image as PNG `ByteArray`
5. Manages lifecycle: load on first request, keep in memory, release on low memory or explicit request

**Channel:** Register `dev.nova.assistant/image_gen` in `NovaChannelRegistrar.kt`
- Method: `generateImage(prompt, size, seed)` → `ByteArray`
- Event: `progress(stage, percent)` for long-running generation

**Model format:**
- Z-Image-Turbo-LiteRT repo contains: `tokenizer.json` + multiple `.tflite` chunks + scheduler weights
- Need Kotlin BPE tokenizer (or Java equivalent) to encode prompt → token IDs
- Need Kotlin DDPM/DDIM scheduler implementation

---

## Phase 2: Flutter Service Wrapper

**New file:**
- `lib/services/image_generation_service.dart`

**Pattern:** Singleton, following `ScreenshotService` pattern exactly.
- `MethodChannel('dev.nova.assistant/image_gen')`
- `Future<Uint8List?> generateImage(String prompt, {ImageSize size, int? seed})`
- Stream progress events to UI
- Check `AdultModePolicy` before sending prompt to native layer

---

## Phase 3: Tool Integration

**New tool:**
- `lib/tools/tool_definitions.dart` — add `generate_image` tool schema

**Modified files:**
- `lib/services/model_orchestrator.dart` — intercept `generate_image` tool calls
- `lib/screens/assistant_screen.dart` — render generated image in chat bubble

**Flow:**
1. Model calls `generate_image` tool with prompt
2. `ModelOrchestrator` intercepts → calls `ImageGenerationService.instance.generateImage()`
3. Native code generates PNG bytes → returns `Uint8List`
4. Stored in `ChatMessage.imageData` on new assistant message
5. `ChatBubble` renders automatically (existing image path)

---

## Phase 4: Model Download & Management

**Modified files:**
- `lib/models/litert_model_catalog.dart` — add diffusion entries
- `lib/models/model_info.dart` — add `NovaModel` enum values for diffusion
- `lib/services/model_manager.dart` — new `installDiffusionModel()` path

**Key difference from chat models:**
- Diffusion models are multi-file (`.tflite` chunks, tokenizer, scheduler)
- `installFromFile()` needs a new branch: extract archive OR download individual files
- No `FlutterGemma.installModel()` call — register with `ImageGenerationService` instead
- Store in same docs dir but separate subdirectory: `{docsDir}/diffusion_models/`

**Model entries:**
```dart
zImageTurbo(
  'Z-Image-Turbo',
  ModelType.diffusion,  // new enum value
  ModelFileType.diffusion, // new enum value
  800,
  false, false, false,
),
flux2Klein(
  'FLUX.2-klein-4B',
  ModelType.diffusion,
  ModelFileType.diffusion,
  2400,
  false, false, false,
);
```

---

## Phase 5: UI Integration

**Modified files:**
- `lib/screens/assistant_screen.dart` — generation state indicator
- `lib/screens/settings_screen.dart` — download trigger with size warning
- `lib/widgets/chat_bubble.dart` — loading state for pending generation

**UI flow:**
1. User sends "generate an image of a cat"
2. If no diffusion model installed → prompt to download (show size, RAM warning)
3. Show progress: "Loading model..." → "Tokenizing..." → "Denoising step 1/4..." → done
4. Generated image appears inline in chat
5. Long-press to save/share (existing image actions)

---

## Files Summary

### New files
| File | Purpose |
|------|---------|
| `android/.../ImageGenerationService.kt` | Native diffusion inference engine |
| `android/.../ImageGenerationModels.kt` | Diffusion model catalog constants |
| `lib/services/image_generation_service.dart` | Flutter singleton wrapper |

### Modified files
| File | Changes |
|------|---------|
| `android/.../NovaChannelRegistrar.kt` | Register `image_gen` channel |
| `android/app/build.gradle.kts` | Add LiteRT/TFLite dependencies |
| `lib/tools/tool_definitions.dart` | Add `generate_image` tool |
| `lib/models/litert_model_catalog.dart` | Add diffusion model entries |
| `lib/models/model_info.dart` | Add diffusion model enum values + `ModelType.diffusion` |
| `lib/services/model_manager.dart` | Add diffusion model install path |
| `lib/services/model_orchestrator.dart` | Handle `generate_image` tool calls |
| `lib/screens/assistant_screen.dart` | Generation state UI |
| `lib/screens/settings_screen.dart` | Download trigger with warnings |
| `lib/widgets/chat_bubble.dart` | Loading state |
| `lib/models/adult_mode_policy.dart` | Image generation policy check |
| `docs/models.md` | Update image generation docs |

---

## Dependencies to Add (android/app/build.gradle.kts)

```kotlin
// LiteRT CompiledModel runtime for diffusion
implementation("org.tensorflow:tensorflow-lite:2.x.x")
implementation("org.tensorflow:tensorflow-lite-gpu:2.x.x") // or use NNAPI
```

Note: `flutter_gemma` bundles its own LiteRT libs. The diffusion pipeline needs its own
TFLite/LiteRT dependency added directly in the app's build.gradle.kts.

---

## Rollout Order

1. **Phase 0:** Feasibility verification on POCO X8 Pro Max
2. **Phase 1:** Native diffusion service + channel registration
3. **Phase 2:** Flutter wrapper + tool definition
4. **Phase 3:** Model download/management
5. **Phase 4:** UI integration + adult mode
6. **Phase 5:** Testing, optimization, memory tuning

---

## Validation

1. `flutter analyze` — no new errors
2. `dart format .` — consistent formatting
3. `flutter test` — existing tests pass
4. **Device test on POCO X8 Pro Max:**
   - Download Z-Image-Turbo model (or FLUX.2-klein if RAM allows)
   - Generate image from prompt: "a cat in space"
   - Verify image renders inline in ChatBubble
   - Verify image is NOT persisted to SharedPreferences (follows existing image stripping pattern)
   - Verify memory usage stays under 10GB total
   - Verify generation completes within 60s on CPU, 15s on NNAPI GPU
5. `adb logcat` during generation to catch NNAPI/LiteRT errors

---

## Key Risks

| Risk | Mitigation |
|------|------------|
| LiteRT multi-graph API not public/stable on Android | Verify in Phase 0 before committing to implementation |
| NNAPI performance poor on MediaTek | Fall back to CPU TFLite Interpreter; acceptable for proof-of-concept |
| Diffusion model OOM on 12GB device | Start with Z-Image-Turbo (smaller); add memory warning UI |
| Tokenizer/scheduler not available in Kotlin | Port a lightweight BPE tokenizer; implement DDPM scheduler |
| Generation blocks UI thread | Run inference on background thread (already implied by MethodChannel async) |

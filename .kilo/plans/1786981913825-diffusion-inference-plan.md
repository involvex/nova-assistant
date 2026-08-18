# Plan: Native Diffusion Image Generation

## Current State
- Flutter side: complete — download, install, tool definition, orchestrator interception, UI
- Native side: `ImageGenerationService.kt` is a skeleton that throws `UnsupportedOperationException`
- `flutter_gemma` does NOT expose any diffusion API (only LLM/VLM chat)
- Models: Z-Image-Turbo (13 `.tflite`, ~9.3GB) and FLUX.2-klein (21 `.tflite`, ~9.6GB)

## Critical Open Question (Ask User First)

**Tokenizer availability**: The repos contain only `.tflite` files — no `tokenizer.json` or vocab file. The text encoder models (`qwen_enc.tflite`, `ke_enc0-2.tflite`) may either:
- (A) Accept raw text input directly (tokenizer embedded in the model graph)
- (B) Require pre-tokenized integer IDs from a separate tokenizer

**My recommendation**: Assume (A) is possible — try passing raw text through the encoder first. If the model expects token IDs, we'll need to find or build a BPE tokenizer for Qwen/KL-based vocabularies. This is the biggest risk.

## Decision: Dependency Approach

**Use TFLite LiteRT directly in `android/app/build.gradle.kts`**, not the `flutter_gemma_litertlm` FFI bindings.

Rationale:
- `flutter_gemma_litertlm` exposes raw `Pointer<LiteRtCompiledModel>` C FFI — unsafe, complex, no error handling
- TFLite's Java API (`CompiledModel`, `Interpreter`, `Delegate`/NNAPI) is the standard Android path
- `flutter_gemma` already bundles LiteRT runtime `.so` libs — adding TFLite directly adds some duplication but avoids version conflicts
- We can use `org.tensorflow:tensorflow-lite` with NNAPI delegate for GPU acceleration

## Architecture

```
Dart (Flutter)
  └─ ImageGenerationService (MethodChannel)
      └─ "dev.nova.assistant/image_gen"
          ├─ generateImage(prompt, size, seed) → ByteArray
          ├─ isModelInstalled(model) → bool
          └─ getInstalledModels() → List<String>

Kotlin (Native)
  └─ ImageGenerationService
      ├─ DiffusionPipeline (per model type)
      │   ├─ TextEncoder (.tflite)
      │   ├─ UNetMain + UNetFinal (.tflite)
      │   └─ VAE (.tflite)
      ├─ Scheduler (DDPM/DDIM — Kotlin implementation)
      ├─ NNAPI delegate for GPU acceleration
      └─ Memory management (load/unload on low RAM)
```

## Execution Order

### Task 1: Add TFLite Dependency
**File**: `android/app/build.gradle.kts`
- Add `org.tensorflow:tensorflow-lite` dependency (version compatible with existing LiteRT runtime)
- Add NNAPI delegate support
- Verify no AAR conflicts with `flutter_gemma`'s bundled LiteRT libs

### Task 2: Model Graph Inspection
**Goal**: Understand exact input/output tensor shapes and types for each `.tflite` file.
- Write a throwaway Android test or use `tflite-support` library to inspect:
  - `qwen_enc.tflite`: input shape (text tokens?), output shape (hidden states?)
  - `zc_main*.tflite`: input shapes (latents + timestep + embeddings?), output shape
  - `zc_final.tflite`: input/output shapes
  - `zvae.tflite`: input (latents), output (image pixels)
- Document: `android/app/src/main/kotlin/dev/nova/assistant/DIFFUSION_MODEL_SPEC.md`

### Task 3: Scheduler Implementation
**File**: `android/app/src/main/kotlin/dev/nova/assistant/DiffusionScheduler.kt`
- Implement DDPM/DDIM scheduler in Kotlin
- Parameters: num_inference_steps (default 4-8 for Turbo), guidance_scale
- Methods: `step(predicted_noise, timestep, latents)` → `next_latents`

### Task 4: Text Encoder Inference
**File**: `android/app/src/main/kotlin/dev/nova/assistant/DiffusionPipeline.kt`
- Load text encoder `.tflite` via `CompiledModel` or `Interpreter`
- Handle input: raw text or token IDs (depends on Task 2 findings)
- Output: text embeddings / pooled embeddings

### Task 5: UNet Inference Loop
**File**: `android/app/src/main/kotlin/dev/nova/assistant/DiffusionPipeline.kt`
- Load UNet `.tflite` models
- Implement denoising loop:
  1. Encode prompt → text embeddings
  2. Encode timestep → time embeddings (via `z_embc.tflite` / `z_embx.tflite`)
  3. For each step:
     - Run UNet main blocks (`zc_main0-5.tflite`) on latents + embeddings
     - Run final block (`zc_final.tflite`) to predict noise
     - Scheduler step to get next latents
- Latent shapes: typically [1, H/8, W/8, 4] for SD-style models

### Task 6: VAE Decoder
**File**: `android/app/src/main/kotlin/dev/nova/assistant/DiffusionPipeline.kt`
- Load VAE `.tflite` (`zvae.tflite`)
- Decode latents → pixel space
- Post-process: clamp [0,1] → [0,255], convert to RGB byte array
- Encode to PNG using Android `Bitmap` + `ByteArrayOutputStream`

### Task 7: Full Pipeline Integration
**File**: `android/app/src/main/kotlin/dev/nova/assistant/ImageGenerationService.kt`
- Wire all components into `generateImage()` method
- Model loading/unloading with lifecycle management
- Error handling with meaningful messages
- Progress reporting via `_progressController`

### Task 8: Memory & Performance
- Implement lazy model loading (load only what's needed per step)
- Add memory pressure listener to unload models
- Benchmark on POCO X8 Pro Max: target <60s for 512x512 on CPU, <15s on NNAPI
- Add `freeRamGateMessage` style guard — warn if insufficient RAM

### Task 9: Progress Reporting & Error Handling
- Stream progress from Kotlin → Flutter via MethodChannel result callback or EventChannel
- Map pipeline stages to progress: "Loading model" → "Encoding prompt" → "Denoising step X/Y" → "Decoding"
- Graceful errors: OOM → suggest smaller size or smaller model; NNAPI failure → fallback to CPU

### Task 10: Testing
- Unit test: scheduler math correctness
- Unit test: tensor shape validation
- Integration test on POCO X8 Pro Max:
  - Simple prompt: "a red apple"
  - Size: 512x512
  - Verify output is valid PNG, non-zero pixel variance
  - Test both Z-Image-Turbo and FLUX.2-klein

## Files to Create/Modify

### New
| File | Purpose |
|------|---------|
| `android/app/src/main/kotlin/dev/nova/assistant/DiffusionPipeline.kt` | Core pipeline: load models, run inference |
| `android/app/src/main/kotlin/dev/nova/assistant/DiffusionScheduler.kt` | DDPM/DDIM scheduler |
| `android/app/src/main/kotlin/dev/nova/assistant/DIFFUSION_MODEL_SPEC.md` | Model graph specs (from Task 2) |

### Modified
| File | Changes |
|------|---------|
| `android/app/build.gradle.kts` | Add TFLite LiteRT + NNAPI dependencies |
| `android/app/src/main/kotlin/dev/nova/assistant/ImageGenerationService.kt` | Implement `generateImage()` (remove skeleton throws) |
| `android/app/src/main/kotlin/dev/nova/assistant/ImageGenerationModels.kt` | Add model graph file lists, input/output specs |
| `lib/services/image_generation_service.dart` | Update progress mapping, add model-specific error messages |
| `lib/models/diffusion_model_info.dart` | Fix sizes (already done), add model-specific metadata |
| `docs/models.md` | Update diffusion section with implementation status |

## Risks

| Risk | Mitigation |
|------|------------|
| Text encoder expects token IDs, not raw text | Task 2 inspection first; if needed, embed a BPE tokenizer |
| NNAPI incompatible with model operators | Fall back to CPU TFLite Interpreter; acceptable but slower |
| OOM during model loading | Lazy load, unload between steps, memory guard before starting |
| TFLite AAR conflicts with flutter_gemma | Test build first; may need `packagingOptions` to resolve |
| Model graph topology different from assumed pipeline | Task 2 inspection resolves this before coding |

## Validation

1. `flutter analyze` + `flutter test` pass
2. Android build succeeds: `flutter build apk --debug`
3. Device test on POCO X8 Pro Max:
   - Install and generate 512x512 image
   - Output is valid PNG with non-uniform pixels
   - Generation completes in <60s
4. `adb logcat` clean of NNAPI/LiteRT errors

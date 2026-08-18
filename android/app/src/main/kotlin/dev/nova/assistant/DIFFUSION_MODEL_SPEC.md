# Diffusion Model Graph Specifications

## Overview

This document records the expected `.tflite` file topology for each supported diffusion model.
These specs drive `ImageGenerationModels.MODEL_SPECS` and `DiffusionPipeline`.

---

## Z-Image-Turbo-LiteRT

**Repo**: `litert-community/Z-Image-Turbo-LiteRT`
**Files**: 13 `.tflite` files
**Tokenizer**: No separate tokenizer — tokenization appears embedded in `qwen_enc.tflite`
**Graph naming**: `zc_*` (zero-crossing main blocks), `z_*` (embeddings / VAE)

| Component | Files | Notes |
|-----------|-------|-------|
| Text Encoder | `qwen_enc.tflite` | Qwen-based encoder, likely accepts raw UTF-8 bytes |
| UNet Main Blocks | `zc_main0.tflite` … `zc_main5.tflite` | 6 sequential blocks |
| UNet Final Block | `zc_final.tflite` | Noise prediction head |
| VAE Decoder | `zvae.tflite` | Latents → RGB pixels |
| Time Embeddings | `z_embc.tflite`, `z_embx.tflite` | Timestep encoding |

**Expected latent shape**: `[1, H/8, W/8, 4]` (standard SD-style)
**Default steps**: 4 (Turbo)
**Guidance scale**: 1.0

---

## FLUX.2-klein-4B-LiteRT

**Repo**: `litert-community/FLUX.2-klein-4B-LiteRT`
**Files**: 21 `.tflite` files
**Tokenizer**: Separate tokenizer files present in `tokenizer/` subdirectory
**Graph naming**: `kc_*` (Kole main blocks), `kce_*` / `ke_*` / `kv_*` (encoder / VAE variants)

| Component | Files | Notes |
|-----------|-------|-------|
| Text Encoder | `ke_enc0.tflite`, `ke_enc1.tflite`, `ke_enc2.tflite` | 3-part encoder |
| UNet Main Blocks | `kc_main0.tflite` … `kc_main5.tflite` | 6 sequential blocks |
| UNet Final Block | `kc_final.tflite` | Noise prediction head |
| VAE Decoder | `kvae.tflite` | Latents → RGB pixels |
| Time Embeddings | `k_embc.tflite`, `k_embx.tflite` | Timestep encoding |

**Expected latent shape**: `[1, H/8, W/8, 4]` (standard SD-style)
**Default steps**: 4
**Guidance scale**: 1.0

---

## Inspection Status

- [ ] Verify exact input/output tensor shapes via TFLite interpreter on device
- [ ] Confirm whether text encoders accept raw text or require pre-tokenized IDs
- [ ] Test NNAPI delegate compatibility with each model graph
- [ ] Document any operator support gaps requiring CPU fallback

# Diffusion Model Graph Specifications

## Overview

This document records the expected `.tflite` file topology for each supported diffusion model.
These specs drive `ImageGenerationModels.MODEL_SPECS` and `DiffusionPipeline`.

---

## Z-Image-Turbo-LiteRT

**Repo**: `litert-community/Z-Image-Turbo-LiteRT`  
**Base**: Tongyi-MAI Z-Image-Turbo (S3-DiT, int8 LiteRT graphs)  
**Files**: 13 `.tflite` files  
**Runtime (upstream)**: LiteRT `CompiledModel` + shared `Environment`, GPU FP32  
**Tokenizer**: **Not in the TFLite graph** — host must run Qwen2 BPE and
`embed_tokens` to build `inputs_embeds`, then feed `qwen_enc.tflite`.

| Component | Files | I/O (256 px) |
|-----------|-------|--------------|
| Text Encoder | `qwen_enc.tflite` (~3.5 GB) | `inputs_embeds[1,64,2560]` → `cap_feats[1,64,2560]` |
| Image embed / refine | `z_embx.tflite`, `z_refx.tflite` | `img[1,256,64]` → `[1,256,3840]` |
| Caption embed / refine | `z_embc.tflite`, `z_refc.tflite` | `cap[1,32,2560]` → `[1,32,3840]` |
| DiT main chunks | `zc_main0.tflite` … `zc_main5.tflite` | `hidden[1,288,3840]` → same |
| Final head | `zc_final.tflite` | `[1,288,3840]` → `[1,288,64]` |
| VAE Decoder | `zvae.tflite` | `latent[1,16,32,32]` → `[1,3,256,256]` |

**Host loop (required):** tokenize + embed → `qwen_enc` → embc/refc + embx/refx
→ concat hidden `[1,288,3840]` → `zc_main0..5` → `zc_final` → unpatchify →
denormalize latents (`/ 0.3611 + 0.1159`) → `zvae`. Cond/uncond CFG with
separate RoPE / pad masks per branch.

**Nova status:** Weights install and path resolution work. Inference is **not**
complete — feeding UTF-8 bytes into `qwen_enc` causes TFLite
`SUM` / reduce prepare failures. The runner fails fast with an explicit error
until the host tokenizer + LiteRT chunk loop land.

---

## FLUX.2-klein-4B-LiteRT

**Repo**: `litert-community/FLUX.2-klein-4B-LiteRT`  
**Files**: 21 `.tflite` files  
**Tokenizer**: Separate tokenizer files may be present under `tokenizer/`

| Component | Files | Notes |
|-----------|-------|-------|
| Text Encoder | `ke_enc0.tflite`, `ke_enc1.tflite`, `ke_enc2.tflite` | 3-part encoder |
| UNet / DiT blocks | `kc_prep`, `kc_double*`, `kc_single*` | Sequential |
| Final | `kc_final.tflite` | Noise / token head |
| VAE Decoder | `kv_vae.tflite` | Latents → RGB |

**Expected latent shape (Nova stub):** `[1, H/8, W/8, 4]` until Hub I/O is verified.

---

## Inspection Status

- [x] Document Z-Image Hub I/O from model card (2026-03)
- [ ] Ship Qwen2 BPE + embed_tokens (or bundled tokenizer assets)
- [ ] Run graphs via LiteRT `CompiledModel` (shared Environment, GPU FP32)
- [ ] Implement embx/refx + embc/refc + CFG + VAE denorm host loop
- [ ] Verify FLUX.2-klein tensor shapes on device
- [ ] Document operator / delegate gaps (VAE OpenCL, qwen_enc GPU compile)

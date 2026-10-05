# Diffusion Model Graph Specifications

## Overview

This document records the expected `.tflite` file topology for each supported diffusion model.
These specs drive `ImageGenerationModels.MODEL_SPECS` and `DiffusionPipeline`.

---

## Z-Image-Turbo-LiteRT

**Repo**: `litert-community/Z-Image-Turbo-LiteRT`  
**Base**: Tongyi-MAI Z-Image-Turbo (S3-DiT, int8 LiteRT graphs)  
**Files**: 13 `.tflite` files (9.78 GB, verified against the upstream tree API)  
**Runtime (upstream)**: LiteRT `CompiledModel` + shared `Environment`, GPU FP32  
**Tokenizer**: **Not in the TFLite graph** — host must run Qwen2 BPE and
`embed_tokens` to build `inputs_embeds`, then feed `qwen_enc.tflite`.

| Component | Files | I/O (256 px) |
|-----------|-------|--------------|
| Text Encoder | `qwen_enc.tflite` (~3.5 GB) | `inputs_embeds[1,64,2560]` → `cap_feats[1,64,2560]` |
| Image embed / refine | `z_embx.tflite`, `z_refx.tflite` | `z_embx`: `img[1,256,64]` → `[1,256,3840]`; `z_refx` also takes `x`, `mask`, `pos[1,256]` |
| Caption embed / refine | `z_embc.tflite`, `z_refc.tflite` | `cap[1,32,2560]` → `[1,32,3840]`; `z_refc` takes **no** `pos` |
| DiT main chunks | `zc_main0.tflite` … `zc_main5.tflite` | `hidden[1,288,3840]` + `x` + `mask` + `pos` → same |
| Final head | `zc_final.tflite` | `hidden[1,288,3840]`, `pos[1,256]` → `[1,288,64]` |
| VAE Decoder | `zvae.tflite` | `latent[1,16,32,32]` → `[1,3,256,256]` |

**Host loop:** tokenize + embed → `qwen_enc` → embc/refc + embx/refx →
concat hidden `[1,288,3840]` (image tokens first) → `zc_main0..5` →
`zc_final` → unpatchify → denormalize latents (`/ 0.3611 + 0.1159`) →
`zvae`. Cond/uncond CFG runs the two branches **sequentially** (graphs are
`[1, …]`, never batched) with a separate context tensor and pad mask per
branch.

Note: `pos[1,256]` is the **timestep embedding**, not position IDs — RoPE is
internal to the graphs and the host must not compute or supply it.

**Nova status:** **Complete.** The host loop runs end to end at 256 px:
`SafetensorsHeaderCheck` → `QwenBpeTokenizer` → `ZImageEmbedLookup` →
`qwen_enc` → `z_embc`/`z_refc` → `z_embx`/`z_refx` → `zc_main0..5` →
`zc_final` → `zvae`. Feeding raw UTF-8 into `qwen_enc` was the original
blocker (it causes TFLite `SUM` / reduce prepare failures); the host now
supplies `inputs_embeds` from the tokenizer + extracted `embed_tokens`.

The graphs are 256 px-fixed, so requests at other sizes clamp to 256 rather
than silently misshape. See `docs/z-image-turbo-litert.md` for the verified
signatures and the derivation of each host formula.

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
- [x] Corrected `pos[1,256]` from position IDs to the timestep embedding
      (RoPE is baked into the graphs) — verified by flatbuffer trace
- [x] Acquire Qwen3 BPE + `embed_tokens` + `t_embedder` at install time and
      extract the two derived tensors from the staged shards
- [x] Implement embx/refx + embc/refc + CFG + VAE denorm host loop
- [x] Fail closed on missing/malformed assets before mmap'ing the encoder
- [ ] Verify FLUX.2-klein tensor shapes on device
- [ ] Re-evaluate GPU delegates (currently CPU-only: fp16 adaLN overflows to
      NaN, and `zvae` fails on the classic TFLite OpenCL delegate)

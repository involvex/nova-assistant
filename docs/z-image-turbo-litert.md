# Z-Image Turbo LiteRT — on-device host loop

Verified 2026-09-29 against three independent sources:

1. **Flatbuffer traces** of the published graphs (`zc_final`, `z_embx`,
   `zc_main0`) from
   [`litert-community/Z-Image-Turbo-LiteRT`](https://huggingface.co/litert-community/Z-Image-Turbo-LiteRT).
2. **`transformer/config.json`** and the **safetensors header** of
   [`Tongyi-MAI/Z-Image-Turbo`](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)
   (read via a ranged HTTP request, no 10 GB download).
3. **diffusers reference implementation** —
   `transformer_z_image.py`, `pipelines/z_image/pipeline_z_image.py`,
   `schedulers/scheduling_flow_match_euler_discrete.py`.

## Correction: `pos[1,256]` is the timestep embedding, not position IDs

An earlier revision of this document treated the 4th graph input as position
IDs and told the host to precompute RoPE. **That was wrong**, and it was
inferred from the model card rather than verified. Flatbuffer traces show the
input is consumed as adaLN conditioning:

`zc_final.tflite`

```
serving_default_args_1[1,256]
  -> LOGISTIC                                  [1,256]
  -> MUL (self)                                [1,256]     # SiLU
  -> FULLY_CONNECTED  adaln_silu  [3840,256]   [1,3840]
  -> MUL against hidden[1,288,3840]
```

`zc_main0.tflite`

```
serving_default_args_3[1,256]
  -> FULLY_CONNECTED  adaln  [15360,256]       [1,15360]
  -> RESHAPE                                  [1,1,15360]
  -> 4x split -> [1,1,3840]
  -> EXP / ADD                                 # adaLN scale & shift
```

So the `256` is a **feature width that happens to equal 16x16** — not a token
count. `15360 = 4 x 3840` is the modulation block width. Consequences:

- **RoPE is internal to the graphs.** The host must not compute or supply
  position IDs. `axes_dims [32,48,48]`, `axes_lens [1536,512,512]`,
  `rope_theta 256.0` are baked into the graph weights.
- The host **must** compute a 256-dim timestep embedding per step and per
  branch. This is the new third required asset (below).

## Status: host loop implemented and verified

The published repo ships **only 13 `.tflite` graphs** (9.78 GB, verified via
the HF tree API) plus a README and one sample PNG. It contains no conversion
scripts and no reference host loop, so everything below had to be derived
from the diffusers reference.

| Extra asset | Source | Size | Needed for |
|---|---|---|---|
| Tokenizer | `Tongyi-MAI/Z-Image-Turbo` `tokenizer/` | ~11 MB | BPE ids for `embed_tokens` |
| `embed_tokens` | `text_encoder/model-00001-of-00003.safetensors` | `[151936,2560]` bf16 = 778 MB (389 MB int8) | `inputs_embeds[1,64,2560]` |
| `t_embedder` MLP | `transformer/diffusion_pytorch_model-00001-of-00003.safetensors` | **~2 MB fp32** | the `pos[1,256]` input |

These do **not** ship with the graphs, so Nova acquires them at install time
from the base checkpoint. The tokenizer (~11 MB) downloads directly; the two
source shards are **not** downloaded at all. `readRemoteSafetensorsHeader`
reads the safetensors header with two ranged requests, and
`extractSafetensorsTensorsRemote` then range-fetches only the byte ranges of
the tensors the host needs — ~780 MB instead of the multi-GB shards, with
nothing staged on disk. `ZImageTensorExtraction.extractMissingRemote` drives
this and validates dtype/shape *before* transferring the large range;
`extractMissing` remains as a fallback for shards already staged locally.

`t_embedder` exact tensors (read from the safetensors header):

| Tensor | dtype | shape |
|---|---|---|
| `t_embedder.mlp.0.weight` | F32 | `[1024, 256]` |
| `t_embedder.mlp.0.bias` | F32 | `[1024]` |
| `t_embedder.mlp.2.weight` | F32 | `[256, 1024]` |
| `t_embedder.mlp.2.bias` | F32 | `[256]` |

`DiffusionModel.inferenceReady` is `true` for Z-Image Turbo. Readiness is
still enforced per-device and in three independent places, so a partial
install fails closed **before** mmap'ing the 3.5 GB text encoder:

1. `ModelManager.findDiffusionModelPath` — the `.tflite` graphs are present.
2. `ModelManager.hasExtraAssets` — tokenizer + both derived tensors exist.
3. `SafetensorsHeaderCheck.checkDerivedAssets` (native) — the derived tensors
   parse and have the expected shape/dtype, so a truncated or tampered file is
   rejected at the door rather than mid-denoise.

## Verified graph signatures

All `float32`, little-endian, row-major. Shapes are fixed at 256 px.

| Graph | Inputs | Output |
|---|---|---|
| `qwen_enc.tflite` (3.5 GB) | `inputs_embeds[1,64,2560]` | `cap_feats[1,64,2560]` |
| `z_embx.tflite` | `img[1,256,64]` | `[1,256,3840]` |
| `z_refx.tflite` | `cap[1,256,3840]`, `x[1,1,256,64]`, `mask[1,1,256,64]`, `pos[1,256]` | `[1,256,3840]` |
| `z_embc.tflite` | `cap[1,32,2560]` | `[1,32,3840]` |
| `z_refc.tflite` | `cap[1,32,3840]`, `x[1,1,32,64]`, `mask[1,1,32,64]` | `[1,32,3840]` |
| `zc_main0..5.tflite` (908 MB each) | `hidden[1,288,3840]`, `x[1,1,288,64]`, `mask[1,1,288,64]`, `pos[1,256]` | `[1,288,3840]` |
| `zc_final.tflite` (1.3 MB) | `hidden[1,288,3840]`, `pos[1,256]` | `[1,288,64]` |
| `zvae.tflite` (50 MB) | `latent[1,16,32,32]` | `[1,3,256,256]` |

Upstream `transformer/config.json`: `dim 3840`, `n_layers 30`, `n_refiner_layers 2`,
`in_channels 16`, `all_patch_size [2]`, `cap_feat_dim 2560`, `t_scale 1000.0`.

### Shape arithmetic

- Latent `32x32` for 256 px -> VAE downscale 8. **16 latent channels** (not 4).
- 2x2 patches -> `16x16 = 256` image tokens, each `16ch x 2 x 2 = 64` values,
  which is exactly `z_embx`'s `[1,256,64]`.
- 256 image + 32 context = **288**, the unified DiT sequence.
- `n_layers 30 = 6 chunks x 5 ExportBlocks` (the trace shows 5 `Linear_adaln`
  ops at `op0/op163/op326/op489/op652` inside `zc_main0`).
- `n_refiner_layers 2 = z_refx + z_refc`. Note `z_refc` takes **no** `pos`
  while `z_refx` does.
- `z_embx` / `z_embc` are the two projectors (64->3840, 2560->3840);
  `z_refx` / `z_refc` are the refiners.

## Host loop

```
tokenize(prompt)                      -> ids
embed_tokens[ids]                     -> inputs_embeds (left-pad to 64)
qwen_enc                              -> cap_feats[1,64,2560]
take first n real rows, n <= 32
pad context to multiple of 32 (repeat last row)   -> cap[32,2560]
z_embc(cap)                           -> ctx[1,32,3840]
z_refc(ctx, x, mask)                  -> ctx[1,32,3840]

per step, per branch (cond / uncond):
  pos[256] = t_embedder((1 - sigma) * 1000)
  patchify latent                     -> img[256, 64]
  z_embx(img)                         -> img_t[1,256,3840]
  z_refx(img_t, x, mask, pos)         -> img_t[1,256,3840]
  concat(img_t, ctx) row-major        -> hidden[1,288,3840]
  zc_main0..5                         -> hidden[1,288,3840]
  zc_final(hidden, pos)               -> v[1,288,64]
  unpatchify                          -> [1,16,32,32]

noise_pred = -(cond + guidance * (cond - uncond))
latent    += (sigma_next - sigma) * noise_pred

latent = latent / 0.3611 + 0.1159     # VAE denormalise
zvae(latent)                          -> [1,3,256,256]
```

The **concat is row-major with image tokens first** (`[x, cap]`), matching
`patchify_and_embed`.

## Verified host math

**patchify** — `transformer_z_image.py::_patchify_image`:

```python
image.view(C, F_t, pF, H_t, pH, W_t, pW)          # (16,1,1,16,2,16,2)
    .permute(1, 3, 5, 2, 4, 6, 0)                 # (1,16,16,1,2,2,16)
    .reshape(F_t*H_t*W_t, pF*pH*pW*C)              # (256, 64)
```

With `F=1, pF=1, pH=pW=2` this reduces to

- token index = `ht * 16 + wt`
- within-patch index = `(dy * 2 + dx) * 16 + c` — **pixel-major,
  channel-minor**. Getting this permutation wrong yields a scrambled or
  per-patch-meshed image even though every tensor shape is correct.
- `unpatchify` is the exact inverse (`.permute(6, 0, 3, 1, 4, 2, 5)`).

**Context padding** — `_pad_with_ids`: pad to a multiple of `SEQ_MULTI_OF = 32`
by **repeating the last row**, pad positions `(0,0,0)`, pad mask `false` for
real tokens and `true` for padding. Because the graphs hard-code 32 context
tokens, the host must **truncate the prompt to <= 32 tokens**; a longer prompt
would need `cap_len = 64` and would not fit the graph. With `n <= 32` the pad
mask is all-`false`, which is consistent with the graphs baking it in.

**Text-encoder padding**: `qwen_enc` takes a fixed `[1,64,2560]` with no
attention-mask input. The encoder is causal, so the host must **left-pad** —
right padding would shift the real tokens' positions and change the output.

**Chat template** — the prompt is *not* tokenized raw. `encode_prompt` applies
the tokenizer's chat template first:

```python
messages = [{"role": "user", "content": prompt}]
prompt = tokenizer.apply_chat_template(messages, tokenize=False,
                                       add_generation_prompt=True,
                                       enable_thinking=True)
```

With no tools and no system message that renders exactly:

```
<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n
```

The host therefore calls `QwenBpeTokenizer.encodeChatPrompt`, which splices
`<|im_start|>`/`<|im_end|>` (ids 151644/151645) as **ids** rather than
encoding the literal text — the GPT-2 pre-tokenizer would split
`<|im_start|>` into `<`, `|`, `im`, `_start`, `|` and never reach those ids.
Skipping the template leaves the encoder conditioned on text unlike anything
in training, which is what made generation degenerate to random colours.

Note the ids are confirmed from the staged `tokenizer.json`, whose
`added_tokens_decoder` has empty `content` for 151643-151645 but names
151646 as `<|object_ref_start|>`, fixing 151644/151645 immediately before it.

**Timestep** — the pipeline feeds `(1000 - t) / 1000` where
`t = sigma * 1000`, i.e. `1 - sigma`. The transformer then applies
`t_scale = 1000.0`, so the `t_embedder` sees `1000 * (1 - sigma)`.

**Timestep embedder** — `TimestepEmbedder(256, mid_size=1024)`:

```python
half = dim // 2                      # 128
freqs = exp(-log(10000) * arange(0, half) / half)
emb   = concat([cos(t * freqs), sin(t * freqs)])   # cos FIRST, then sin
t_emb = Linear(1024 -> 256 after SiLU)(emb)         # mlp.0, SiLU, mlp.2
```

`nn.Linear` is `x @ W.T + b`, and the safetensors weights are `[1024,256]` and
`[256,1024]`, so both are row-major `[out, in]`.

**Sigmas** — `get_default_z_image_sigmas(n) = linspace(1.0, 1/n, n)`, i.e. for
8 steps `[1.0, 0.875, 0.75, 0.625, 0.5, 0.375, 0.25, 0.125]`. These are then
resolution-shifted because the Z-Image scheduler sets `use_dynamic_shifting`:

```python
mu = (max_shift - base_shift)/(max_seq_len - base_seq_len) * seq_len
    + base_shift - ((max_shift - base_shift)/(max_seq_len - base_seq_len)) * base_seq_len
sigmas = exp(mu) / (exp(mu) + (1/sigma - 1))     # time_shift_type = "exponential"
```

with `base_seq_len 256`, `max_seq_len 4096`, `base_shift 0.5`, `max_shift 1.15`.
At 256 px `image_seq_len = (32/2)*(32/2) = 256`, which gives `mu = 0.5`. A
**terminal sigma of 0.0 is appended**, so the schedule has `steps + 1` entries.

**CFG** — `pred = cond + guidance * (cond - uncond)`, and the negation is
applied **after** CFG, not inside the branches:

```python
noise_pred = torch.stack([...])
noise_pred = -noise_pred
```

**Euler step** — `FlowMatchEulerDiscreteScheduler.step`:
`prev_sample = sample + (sigma_next - sigma) * model_output`, `float32`.

**VAE denormalise** — `latents / scaling_factor + shift_factor` with
`scaling_factor 0.3611`, `shift_factor 0.1159` (from the upstream VAE config;
`latent_channels 16`, 8x downscale).

## Two details that silently corrupt the image

1. **cond and uncond prompts have different token counts**, so each branch needs
   its own context tensor, its own padding length, and its own `cap_feats`. The
   DiT is not batched over branches — the graphs are `[1, ...]`, so the host must
   run the two branches **sequentially** and reuse no context state.
2. **The latent must be denormalised before `zvae`.** Skipping the
   `/0.3611 + 0.1159` produces a washed-out, low-contrast image.

## Runtime notes

- Graphs should run through LiteRT `CompiledModel` with
  `GpuOptions(precision = FP32)` — fp16 adaLN overflows to NaN.
- One shared `Environment` across every graph; a null Environment leaks the
  OpenCL context and aborts after ~20 FP32 compiles.
- The pad-token MUL-after-FC must move to the host (it is a BC compile wall).
- Head/tail graphs are faster on CPU than GPU: `z_embc` 2 ms vs 6 ms,
  `zc_final` 14 ms vs 35 ms, `z_refc` 81 ms vs 100 ms.
- `zvae.tflite` **fails on the classic TFLite OpenCL delegate** ("cannot build
  an image of that size"). It only ran on the Hexagon NPU in the published
  sweep. Nova must not assume a GPU delegate for the VAE.

## Cost

`zc_main*` dominates: 660 ms/step/graph on GPU, 3.6 s/step on CPU. Six chunks
x 2 branches x N steps. At 8 steps that is ~63 s of DiT alone on a Pixel 8a
GPU, plus a 3.5 GB text encoder run. This is a multi-minute operation on a
phone, not a snappy one.

## Implementation

| File | Role |
|---|---|
| `ZImageHostLoop.kt` | host-side math (pure JVM, no Android dependencies) |
| `ZImagePipeline.kt` | orchestration: phases, CFG branches, CFG/Euler loop |
| `ZImageGraphs.kt` | per-phase lazy `Interpreter` lifecycle over the 13 graphs |
| `QwenBpeTokenizer.kt` | Qwen3 BPE from `tokenizer/` (pre-tokenizer + byte-level) |
| `ZImageEmbedLookup.kt` | mmap row gather from `embed_tokens.safetensors` |
| `TEmbedderWeightsLoader.kt` | loads the MLP into [ZImageHostLoop.TimestepEmbedderWeights] |
| `SafetensorsHeaderCheck.kt` | native pre-flight shape/dtype gate |
| `DiffusionPipeline.kt` | `generateZImage` entry; generic SD path for FLUX.2-klein |

Asset acquisition is Dart-side: `safetensors_extractor.dart` (local +
ranged-HTTP header reading and tensor slicing) and
`zimage_tensor_extraction.dart` (the two extractions plus post-extract
verification).

Covered by 56 JVM unit tests in
`android/app/src/test/kotlin/dev/nova/assistant/`, including
`ZImagePipelineTest`, which drives the full host loop end to end at 256 px
through a fake graph executor.

Native prompt path (also pure JVM, unit-tested):

- `QwenBpeTokenizer.kt` — byte-level BPE over staged `tokenizer/vocab.json`
  + `tokenizer/merges.txt` (GPT-2 family; Qwen3 vocab 151936).
- `SafetensorsHeaderCheck.kt` — fail-closed header pre-check mirroring the
  Dart `verifyDerivedAssets` (exact dtype + shape, offsets inside the file).
  Runs before the host touches the 778 MB matrix.
- `ZImageEmbedLookup.kt` — BF16 row gather + left-pad to
  `inputs_embeds[1,64,2560]` (`prepareInputsEmbeds`), reading only the
  referenced rows via positional I/O instead of a full mmap.
- `DiffusionPipeline.generateImage` (Z-Image branch): header pre-check →
  Qwen3 tokenize → embed lookup → `TEmbedderWeightsLoader` →
  `ZImagePipeline.generate` (branch contexts, CFG DiT loop over
  `z_embx/z_refx/z_embc/z_refc` + `zc_main0..5` + `zc_final`, Euler updates,
  `zvae` decode) → PNG. Graphs open lazily per phase and each phase is
  released to bound peak RSS; every graph input is checked against its
  runtime tensor shape before the call.

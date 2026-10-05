# Changelog

All notable changes to Nova Assistant are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Z-Image Turbo on-device image generation: complete native host loop
  (Qwen3 BPE tokenizer, `embed_tokens` lookup, `t_embedder` timestep MLP,
  patchify/unpatchify, CFG + Euler denoising, VAE decode). Covers the
  previously unrunnable 14-graph LiteRT set end to end at 256 px.
- Z-Image text encoder is now fed chat-templated prompts. `pipeline_z_image.py`
  applies the Qwen3 chat template before tokenising
  (`<|im_start|>user\n…<|im_end|>\n<|im_start|>assistant\n`), but the host
  loop passed the bare string. The encoder saw out-of-distribution text, the
  conditioning was near-noise, and generation produced random colours rather
  than a recognisable image. `QwenBpeTokenizer.encodeChatPrompt` splices the
  special tokens as ids, because the GPT-2 pre-tokenizer would otherwise
  shred `<|im_start|>` into separate pieces.
- Image-gen prompts no longer keep the punctuation users type between the ask
  and the subject: "generate an image of: a cat" produced the literal prompt
  `": a cat"`, and a leading `:` degrades the diffusion prompt.
- Image-gen asks behind a greeting ("hey, generate an image of a fox") are
  recognised instead of falling through to the LLM, which had no reliable way
  to emit the tool call and simply echoed the message. Greeting stripping runs
  before the "about existing images" guard, so non-image asks are unaffected.
- Beginner chat mode no longer drops generated images: its streaming
  `copyWith` omitted `imageData`, so a successful generation rendered as
  "Generated an image for …" with no image attached.
- Direct TFLite ByteBuffers are pooled per tensor slot and released with their
  interpreter. Allocating ~22 MB of fresh direct buffers per graph call left
  hundreds of MB unreclaimed (direct memory is only freed on GC), which is
  what pushed PSS past MIUI's hard 6 GB third-party cap and got the process
  killed mid-generation.
- Ranged-HTTP safetensors extraction (`readRemoteSafetensorsHeader`,
  `extractSafetensorsTensorsRemote`). Acquiring the Z-Image host tensors now
  transfers only the ~780 MB actually needed instead of staging both
  multi-GB base-checkpoint shards — a large cut in download time and phone
  storage. Falls back to locally staged shards when a server ignores
  `Range`.

### Changed

- Migrate on-device inference from discontinued `flutter_gemma` packages to Flutter Edge AI 2.0 (`flutter_edge_ai`, `flutter_edge_ai_litertlm`, `flutter_edge_ai_mediapipe`, `flutter_edge_ai_speech`). Raise minimum Flutter SDK to 3.44.

### Fixed

- Z-Image Turbo no longer produced colour mush instead of an image. The spec
  forced `guidance_scale = 1.0`, but Z-Image Turbo is guidance-distilled and
  `pipeline_z_image.py`'s own example runs `guidance_scale = 0.0` (where
  `do_classifier_free_guidance` is `guidance_scale > 0`). Running classifier-
  free guidance over a distilled checkpoint oversaturates the output. The
  spec now ships `steps = 8`, `guidance = 0.0` to match the reference, and
  `ZImagePipeline` skips the uncond branch entirely when guidance is zero.
- Safetensors extraction no longer buffers a whole tensor in the Dart heap
  before writing. `embed_tokens` is a 778 MB matrix; the `copy` callback now
  streams straight into the destination file.
- Z-Image Turbo no longer allocates an unused latent buffer or emits a
  misleading "Preparing latents" progress tick before dispatching to the
  host-loop path.
- Installed diffusion models that still need their host assets (tokenizer,
  `embed_tokens`, `t_embedder`) are no longer a dead end. Settings now shows
  an "assets needed for generation" state with a one-tap download, and the
  generation sheet offers the same action on that error. Previously the only
  route was uninstalling and re-downloading the multi-GB graphs.

## [0.4.8] - 2026-09-22

### Changed

- v0.4.8
## [0.4.7] - 2026-08-20

### Changed

- Activate keyword-triggered on-device image generation in chat flow
### Added

- Keyword-triggered image generation: ask "generate an image of a sunset over mountains" and Nova will use an on-device diffusion model (Z-Image-Turbo or FLUX.2-klein) to create and display the result inline in the chat. Image generation is now reachable from the Flutter chat layer — the tool wires through `_wantsGenerateImage`, `_toolsForQuery`, `generate_image` aliases, and the `imageData` rendering path.

### Fixed

- Image generation tool (`generate_image`) was implemented end-to-end on the native side but disconnected from the chat UI; it is now exposed to the model and its output is rendered in the chat bubble.






## [0.4.6] - 2026-08-11

### Changed

- v0.4.6
## [0.4.5] - 2026-07-28

### Changed

- v0.4.5
## [0.4.4] - 2026-07-27

### Changed

- v0.4.4
## [0.4.3] - 2026-07-24

### Changed

- v0.4.3
## [0.4.2] - 2026-07-19

### Changed

- v0.4.2

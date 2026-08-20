---
layout: default
title: Models
---

# Models

## Built-in catalog

| Model | Size | Vision | Thinking | Tools | Format |
|-------|------|--------|----------|-------|--------|
| SmolLM-135M | 135MB | No | No | Yes | `.task` |
| FastVLM-0.5B | 500MB | Yes | No | Yes | `.litertlm` |
| Gemma 3 1B | 500MB | No | No | Yes | `.litertlm` |
| Gemma 4 E2B | 2400MB | Yes | Yes | Yes | `.litertlm` |

Defined in `lib/models/model_info.dart`. Selection logic lives in `ModelSelector`.

## Auto selection

- Short query (≤8 words) → SmolLM
- Image attached → vision-capable model
- Thinking mode → Gemma 4 E2B
- Default heavy → Gemma 4 E2B

## Import your own model

1. Obtain a **`.litertlm`** or **`.task`** file (GGUF is not supported).
2. In app: **Settings → AI Models → Import from storage**, or onboarding import.
3. Or ask an agent: *use nova_dev to configure my own model*.

Canonical filenames matter: downloads must register as e.g. `gemma-4-E2B-it.litertlm`, not temp names like `nova_download_<ms>_…`.

## HuggingFace

- Optional token in Settings for gated repos
- Model Browser searches HF and downloads into app documents
- Prefer authenticated downloads if you hit 401/403

## Context window (Gemma 4)

On **Android**, Gemma 4 E2B uses a **2048-token KV cache** by default to limit RAM use. That caps how long a single message can be once chat history and system overhead are counted.

Enable **High context window** in **Settings** to raise the KV limit to **4096** and allow substantially longer messages (at the cost of more RAM — avoid on ≤6 GB phones).

When a thread gets long, **Compact context** (manual button in chat) or **Auto-compact context** (Settings, on by default) summarizes older turns so new messages still fit without starting a new chat. The full message list stays visible; only the inference session is replayed from the summary plus recent turns.

## Adult mode

**Adult mode** (Settings, default off) is a local-only preference that appends a short system-prompt suffix so Nova answers legal adult topics more directly. It does not unlock illegal content and cannot fully override the base model’s own refusals.

## RAM guidance

| Device RAM | Recommendation |
|------------|----------------|
| ≤6 GB | SmolLM or Gemma 3 1B for soak tests |
| 8 GB+ | Gemma 4 E2B OK; close heavy apps first |
| Debug all day | Enable battery/idle unload; avoid continuous screen capture |

Onboarding uses **total device RAM** (not only free RAM): phones under ~6.5 GB
default to **SmolLM** so a wiped POCO F1 does not start a 2.4 GB Gemma 4 download
it cannot load for chat.

Android idle unload is shorter (~2 minutes) to reduce LMK pressure.

## On-device image generation

Repos such as
[FLUX.2-klein-4B-LiteRT](https://huggingface.co/litert-community/FLUX.2-klein-4B-LiteRT)
and
[Z-Image-Turbo-LiteRT](https://huggingface.co/litert-community/Z-Image-Turbo-LiteRT)
are **LiteRT `CompiledModel` multi-graph diffusion pipelines** (many `.tflite`
chunks + host tokenizer/scheduler), not `flutter_gemma` / LiteRT-LM chat
(`.litertlm` / `.task`) models.

Nova ships a separate native LiteRT GPU diffusion pipeline for on-device image
generation. Ask "generate an image of a sunset over mountains" and Nova will
run the selected diffusion model (Z-Image-Turbo or FLUX.2-klein) entirely on
device, then display the result inline in the chat. Diffusion models are
large (~800 MB – 2.4 GB); download them via Settings → Models.

This feature is **Android-only** in the current build (web and other platforms
fall back to remote LAN).

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

## RAM guidance

| Device RAM | Recommendation |
|------------|----------------|
| ≤6 GB | SmolLM or Gemma 3 1B for soak tests |
| 8 GB+ | Gemma 4 E2B OK; close heavy apps first |
| Debug all day | Enable battery/idle unload; avoid continuous screen capture |

Android idle unload is shorter (~2 minutes) to reduce LMK pressure.

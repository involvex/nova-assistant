---
layout: default
title: Remote LAN inference
---

<link rel="stylesheet" href="{{ '/assets/css/nova-docs.css' | relative_url }}">

# Remote LAN inference

Use a PC on your Wi‑Fi to run **large / GGUF** models and stream answers into Nova.
On-device LiteRT remains the default. On-device GGUF is **not** supported in the same APK.

## Host (llama-server)

```bash
llama-server -m /path/to/model.gguf --host 0.0.0.0 --port 8080
```

Note your PC’s LAN IP (e.g. `192.168.1.42`). Keep the host on a private network;
use a firewall and an optional API token.

## Nova client

1. Settings → **Remote LAN inference**
2. Backend → **Remote LAN** (persists immediately)
3. Base URL → `http://192.168.1.42:8080`
4. Model id → whatever your server expects (often the GGUF name or `local-model`)
5. Optional API token
6. **Test connection**, then **Save** (URL fields also save when you leave the screen)

When Remote LAN is active:

- Chat streams from the LAN host (composer shows **Remote LAN**)
- Local LiteRT is **not** loaded for chat (pre-warm is skipped)
- The “No AI model installed” banner is hidden
- Android allows cleartext `http://` to LAN hosts via network security config

Deterministic device shortcuts (alarms / open app) still run on the phone; full
tool-calling via the remote model is not enabled in v1.

## Security

- Trusted private Wi‑Fi only
- Do not port-forward the host to the public internet
- API tokens are stored in secure prefs and are **not** included in settings backup

## Related

- [Models](models.md) — on-device catalog
- Plan: `docs/superpowers/plans/2026-07-17-lan-remote-inference.md` (repo only; not published)

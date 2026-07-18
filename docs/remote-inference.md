---
layout: default
title: Remote LAN inference
---

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
2. Backend → **Remote LAN**
3. Base URL → `http://192.168.1.42:8080`
4. Model id → whatever your server expects (often the GGUF name or `local-model`)
5. Optional API token
6. **Test connection**, then **Save**

Chat messages then stream from the LAN host. Deterministic device shortcuts
(alarms / open app) still run on the phone; full tool-calling via the remote
model is not enabled in v1.

## Security

- Trusted private Wi‑Fi only
- Do not port-forward the host to the public internet
- API tokens are stored in app prefs and are **not** included in settings backup

## Related

- [Models](models.md) — on-device catalog
- Plan: `docs/superpowers/plans/2026-07-17-lan-remote-inference.md`

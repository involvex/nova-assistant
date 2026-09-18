---
layout: default
title: Contributing
---

# Contributing

## Workflow

1. Fork / branch from `main` (`feature/…`, `fix/…`, `docs/…`)
2. Implement with tests where practical
3. Run locally:

```bash
dart format .
flutter analyze --no-pub
flutter test
```

4. Open a PR — CI runs analyze, test, and Android debug APK build

## Commits

Conventional Commits:

```
feat: …
fix: …
docs: …
refactor: …
test: …
chore: …
```

## Code style

See [AGENTS.md](agents.md) — trailing commas, `prefer_final_locals`, single quotes, `SizedBox` for spacing, no drive-by refactors.

## Docs site

Source lives in `docs/`. Pushes that touch docs deploy via GitHub Pages (`.github/workflows/docs.yml`).

Enable Pages in the repo: **Settings → Pages → Source: GitHub Actions**.

## Agent skill

Shareable skill: [`.cursor/skills/nova-dev/SKILL.md`](../.cursor/skills/nova-dev/SKILL.md)
(canonical). Synced copies for other agents:

| Path | Consumer |
|------|----------|
| `.cursor/skills/nova-dev/` | Cursor |
| `.agents/skills/nova-dev/` | Codex / Agents SDK |
| `.claude/skills/nova-dev/` | Claude Code (junction → `.agents`) |

```powershell
./scripts/link-nova-dev-skill.ps1          # copy Cursor → agents, junction claude
./scripts/link-nova-dev-skill.ps1 -LiveLink # junction agents → Cursor (single edit)
```

```bash
./scripts/link-nova-dev-skill.sh
./scripts/link-nova-dev-skill.sh --live
```

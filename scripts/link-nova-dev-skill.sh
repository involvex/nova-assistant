#!/usr/bin/env bash
# Recreate / sync the nova-dev skill across agent skill roots.
#
# Canonical (edit here):  .cursor/skills/nova-dev/
# Codex / Agents SDK:     .agents/skills/nova-dev/
# Claude Code:            .claude/skills/nova-dev/ -> .agents/skills/nova-dev
#
# Usage:
#   ./scripts/link-nova-dev-skill.sh           # sync copy + claude symlink
#   ./scripts/link-nova-dev-skill.sh --live    # also symlink .agents -> .cursor

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CURSOR="$ROOT/.cursor/skills/nova-dev"
AGENTS="$ROOT/.agents/skills/nova-dev"
CLAUDE="$ROOT/.claude/skills/nova-dev"
LIVE=0
[[ "${1:-}" == "--live" ]] && LIVE=1

if [[ ! -f "$CURSOR/SKILL.md" ]]; then
  echo "Canonical skill missing: $CURSOR/SKILL.md" >&2
  exit 1
fi

rm -rf "$CLAUDE" "$AGENTS"

if [[ "$LIVE" -eq 1 ]]; then
  ln -s "../../.cursor/skills/nova-dev" "$AGENTS"
  echo "Linked .agents/skills/nova-dev → .cursor/skills/nova-dev"
else
  mkdir -p "$AGENTS"
  cp "$CURSOR/SKILL.md" "$AGENTS/SKILL.md"
  echo "Copied SKILL.md → .agents/skills/nova-dev/"
fi

ln -s "../../.agents/skills/nova-dev" "$CLAUDE"
echo "Linked .claude/skills/nova-dev → .agents/skills/nova-dev"
echo "Done. Edit canonical file: .cursor/skills/nova-dev/SKILL.md"

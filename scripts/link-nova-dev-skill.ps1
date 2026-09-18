# Recreate / sync the nova-dev skill across agent skill roots.
#
# Canonical (edit here):  .cursor/skills/nova-dev/
# Codex / Agents SDK:     .agents/skills/nova-dev/   (copy, then optional junction)
# Claude Code:            .claude/skills/nova-dev/   (junction → .agents)
#
# Usage:
#   ./scripts/link-nova-dev-skill.ps1           # sync copy + claude junction
#   ./scripts/link-nova-dev-skill.ps1 -LiveLink # also junction .agents → .cursor

param(
  [switch]$LiveLink
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$cursor = Join-Path $root '.cursor\skills\nova-dev'
$agents = Join-Path $root '.agents\skills\nova-dev'
$claude = Join-Path $root '.claude\skills\nova-dev'
$skill = Join-Path $cursor 'SKILL.md'

if (-not (Test-Path $skill)) {
  throw "Canonical skill missing: $skill"
}

function Remove-LinkOrDir([string]$path) {
  if (-not (Test-Path $path)) { return }
  $item = Get-Item $path -Force
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    cmd /c rmdir "$path" | Out-Null
  } else {
    Remove-Item $path -Recurse -Force
  }
}

Remove-LinkOrDir $claude
Remove-LinkOrDir $agents

if ($LiveLink) {
  cmd /c mklink /J "$agents" "$cursor" | Out-Null
  Write-Host "Linked .agents/skills/nova-dev → .cursor/skills/nova-dev"
} else {
  New-Item -ItemType Directory -Path $agents -Force | Out-Null
  Copy-Item $skill (Join-Path $agents 'SKILL.md') -Force
  Write-Host "Copied SKILL.md → .agents/skills/nova-dev/"
}

cmd /c mklink /J "$claude" "$agents" | Out-Null
Write-Host "Linked .claude/skills/nova-dev → .agents/skills/nova-dev"
Write-Host "Done. Edit canonical file: .cursor/skills/nova-dev/SKILL.md"
if (-not $LiveLink) {
  Write-Host "Re-run with -LiveLink for single-edit junctions, or re-run without it before commit."
}

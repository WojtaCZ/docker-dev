#!/usr/bin/env bash
# Install usage pacing for the HOST's Claude Code (the container gets it baked in):
#   ~/.local/bin/claude-usage          -> this repo's scripts/claude-usage.sh (symlink)
#   ~/.claude/skills/usage-pacing      -> this repo's claude-baseline/skills/usage-pacing (symlink)
#   ~/.claude/settings.json            SessionStart, PostToolUse, PreToolUse, Subagent* hooks added (idempotent;
#                                      a .bak copy is kept)
# Needs tmux on the host (Arch: sudo pacman -S tmux).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$HOME/.local/bin" "$HOME/.claude/skills"
ln -sfn "$REPO/scripts/claude-usage.sh" "$HOME/.local/bin/claude-usage"
ln -sfn "$REPO/claude-baseline/skills/usage-pacing" "$HOME/.claude/skills/usage-pacing"

S="$HOME/.claude/settings.json"
[ -f "$S" ] || echo '{}' > "$S"
cp "$S" "$S.bak"
python3 - "$S" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
hooks = d.setdefault("hooks", {})
def add(event, entry):
    lst = hooks.setdefault(event, [])
    if not any(h.get("command") == "claude-usage hook" for e in lst for h in e.get("hooks", [])):
        lst.append(entry)
add("SessionStart", {"matcher": "startup|resume|compact",
                     "hooks": [{"type": "command", "command": "claude-usage hook", "timeout": 15}]})
add("PostToolUse", {"hooks": [{"type": "command", "command": "claude-usage hook", "timeout": 15}]})
add("PreToolUse", {"matcher": "Agent|Task|Workflow",
                   "hooks": [{"type": "command", "command": "claude-usage hook", "timeout": 60}]})
for ev in ("SubagentStart", "SubagentStop"):
    add(ev, {"hooks": [{"type": "command", "command": "claude-usage hook", "timeout": 10}]})
open(p, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
command -v tmux >/dev/null || echo "WARN: tmux missing; install it (sudo pacman -S tmux) or probes fail" >&2
echo "installed; new Claude sessions pick it up"

#!/usr/bin/env bash
# Per-project work notes, so Claude can resume after a usage limit or a container crash.
# Runs from Claude hooks (claude-baseline/settings.json).
#
#   work-notes resume     SessionStart: prepare .claude-notes/ and print the notes so far
#   work-notes subagent   SubagentStart: tell the subagent where its own notes go (JSON on stdout)
#
# Notes live in <project>/.claude-notes/, inside the bind-mounted project, so they are on
# the host and survive anything that happens to the container:
#   progress.md             the main session: goal, status, next steps, decisions
#   agents/<name>.md        one file per subagent (no two writers share a file)
#
# Contract (tests/unit/work-notes.sh):
#   * ALWAYS exits 0; a hook must never break a session.
#   * Does nothing when the project has a `.no-notes` file or DEV_NOTES=0, or when the
#     directory is / or $HOME.
#   * Never commits. In a git repo it adds `.claude-notes/` to .git/info/exclude (local,
#     untracked) so the notes never show up as changes.

set -uo pipefail

MAX_LINES=120   # how much of progress.md is replayed at session start

mode="${1:-resume}"
dir="$PWD"
top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$top" ] && dir="$top"
dir="$(cd "$dir" 2>/dev/null && pwd -P)" || exit 0
notes="$dir/.claude-notes"

[ "${DEV_NOTES:-1}" = "0" ] && exit 0
[ -e "$dir/.no-notes" ] && exit 0
[ "$dir" = "/" ] && exit 0
[ "$dir" = "$(cd "${HOME:-/nonexistent}" 2>/dev/null && pwd -P)" ] && exit 0

mkdir -p "$notes/agents" 2>/dev/null || exit 0

if [ -n "$top" ]; then
    excl="$(git -C "$top" rev-parse --git-path info/exclude 2>/dev/null)"
    case "$excl" in /*) ;; *) excl="$top/$excl" ;; esac
    if [ -n "$excl" ] && ! grep -qxF '.claude-notes/' "$excl" 2>/dev/null; then
        mkdir -p "$(dirname "$excl")" 2>/dev/null
        echo '.claude-notes/' >> "$excl" 2>/dev/null
    fi
fi

case "$mode" in
resume)
    echo "work-notes: $notes (keep progress.md current; see 'Work notes' in your memory)"
    if [ -s "$notes/progress.md" ]; then
        echo "--- progress.md (last session's state; continue from here) ---"
        tail -n "$MAX_LINES" "$notes/progress.md"
        echo "--- end progress.md ---"
    else
        echo "No progress.md yet: create it when you start the task."
    fi
    agents="$(find "$notes/agents" -maxdepth 1 -name '*.md' -printf '%TY-%Tm-%Td %TH:%TM  %f\n' 2>/dev/null | sort -r | head -10)"
    [ -n "$agents" ] && printf 'Subagent notes in %s/agents (newest first):\n%s\n' "$notes" "$agents"
    ;;
subagent)
    in="$(cat 2>/dev/null || true)"
    name="$(printf '%s' "$in" | jq -r '[.agent_type // "agent", ((.agent_id // "") | .[0:8])] | map(select(. != "")) | join("-")' 2>/dev/null)"
    name="$(printf '%s' "${name:-agent}" | tr -c 'A-Za-z0-9._-' '_')"
    msg="Keep work notes: your container may crash or hit a usage limit and be resumed later. Keep your own file $notes/agents/$name.md (create it first): task, steps done, current step, findings, what remains. Append a line after every meaningful step, before long-running commands. Do not edit progress.md; the main session owns it. Put anything the main session must know in your final report."
    jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $m}}' 2>/dev/null
    ;;
esac
exit 0

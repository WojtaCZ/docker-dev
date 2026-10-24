#!/usr/bin/env bash
# work-notes: per-project notes hook. Run: bash tests/run-unit.sh tests/unit/work-notes.sh
set -uo pipefail

NOTES="${NOTES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/work-notes.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok  $1"; else echo "FAIL: $1: expected [$2] got [$3]" >&2; fails=$((fails + 1)); fi; }
has() { if grep -qF -- "$2" <<< "$3"; then echo "  ok  $1"; else echo "FAIL: $1: [$2] not in [$3]" >&2; fails=$((fails + 1)); fi; }

git init -q "$T/repo"; mkdir -p "$T/repo/sub" "$T/plain"

out="$(cd "$T/repo/sub" && "$NOTES" resume)"; rc=$?
check "exit 0" 0 "$rc"
check "notes dir at repo root" yes "$([ -d "$T/repo/.claude-notes/agents" ] && echo yes || echo no)"
has "no progress yet" "No progress.md yet" "$out"
check "excluded locally" 1 "$(grep -cxF '.claude-notes/' "$T/repo/.git/info/exclude")"
(cd "$T/repo" && "$NOTES" resume >/dev/null); check "exclude not duplicated" 1 "$(grep -cxF '.claude-notes/' "$T/repo/.git/info/exclude")"
check "git sees no changes" "" "$(git -C "$T/repo" status --porcelain)"

printf 'goal: X\nnext: Y\n' > "$T/repo/.claude-notes/progress.md"
echo x > "$T/repo/.claude-notes/agents/explore-1.md"
out="$(cd "$T/repo" && "$NOTES" resume)"
has "replays progress" "next: Y" "$out"
has "lists subagent notes" "explore-1.md" "$out"

seq 1 500 > "$T/repo/.claude-notes/progress.md"
out="$(cd "$T/repo" && "$NOTES" resume)"
has "tail kept" "500" "$out"; has "head dropped" "no" "$(grep -qx 1 <<< "$out" && echo yes || echo no)"

out="$(cd "$T/repo" && echo '{"agent_type":"Explore","agent_id":"abcdef1234567"}' | "$NOTES" subagent)"
check "subagent json" SubagentStart "$(jq -r .hookSpecificOutput.hookEventName <<< "$out")"
has "subagent path" ".claude-notes/agents/Explore-abcdef12.md" "$(jq -r .hookSpecificOutput.additionalContext <<< "$out")"
out="$(cd "$T/repo" && echo 'garbage' | "$NOTES" subagent)"; check "garbage stdin exit 0" 0 "$?"

out="$(cd "$T/plain" && "$NOTES" resume)"; check "non-git dir works" yes "$([ -d "$T/plain/.claude-notes" ] && echo yes || echo no)"

touch "$T/plain/.no-notes"; rm -rf "$T/plain/.claude-notes"
out="$(cd "$T/plain" && "$NOTES" resume)"; check ".no-notes -> silent" "" "$out"; check ".no-notes -> no dir" no "$([ -d "$T/plain/.claude-notes" ] && echo yes || echo no)"
out="$(cd "$T/repo" && DEV_NOTES=0 "$NOTES" resume)"; check "DEV_NOTES=0 -> silent" "" "$out"
out="$(cd / && "$NOTES" resume)"; check "/ skipped" "" "$out"
out="$(cd "$HOME" && "$NOTES" resume)"; check "HOME skipped" "" "$out"

[ "$fails" = 0 ] && echo "work-notes: all passed" || exit 1

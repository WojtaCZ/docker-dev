#!/usr/bin/env bash
# Every skill is in directory form (<name>/SKILL.md) with frontmatter Claude Code
# indexes: only that form triggers on its own. Plain bash; run anywhere.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SK="$ROOT/claude-baseline/skills"
fails=0
bad() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }

flat=$(find "$SK" -maxdepth 1 -type f -name '*.md' | sort)
[ -z "$flat" ] || bad "flat skill files remain (they never trigger on their own): $(echo "$flat" | xargs -n1 basename | tr '\n' ' ')"

n=0
for d in "$SK"/*/; do
    name="$(basename "$d")"; f="$d/SKILL.md"; n=$((n + 1))
    [ -f "$f" ] || { bad "$name: no SKILL.md"; continue; }
    [ "$(head -1 "$f")" = "---" ] || { bad "$name: SKILL.md does not start with frontmatter"; continue; }
    fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")"
    got="$(sed -n 's/^name:[[:space:]]*//p' <<< "$fm" | head -1 | sed 's/^["'\'']//; s/["'\'']$//')"
    [ "$got" = "$name" ] || bad "$name: frontmatter name is [$got]"
    desc="$(sed -n 's/^description:[[:space:]]*//p' <<< "$fm" | head -1)"
    [ "${#desc}" -ge 60 ] || bad "$name: description shorter than 60 chars (${#desc})"
    case "$name" in .gitkeep) ;; esac
done
[ "$n" -ge 40 ] || bad "expected >= 40 skill directories (37 imported + 3 new), found $n"

for s in arm-project-layout telink-sdk-mount embedded-tooling-reference; do
    [ -f "$SK/$s/SKILL.md" ] || bad "new skill $s missing"
done

# Parity: every skill the children shipped is still here.
missing=$(grep '^skill|' "$ROOT/tests/parity/manifest.txt" | cut -d'|' -f2 | while read -r s; do [ -d "$SK/$s" ] || echo "$s"; done)
[ -z "$missing" ] || bad "manifest skills missing: $missing"

# The global-CROSS_PREFIX wording must be gone from skill text.
stale=$(grep -rl 'exported by each leaf image' "$SK" 2>/dev/null || true)
[ -z "$stale" ] || bad "skills still claim CROSS_PREFIX is exported by each leaf image: $stale"

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "skills: all passed ($n skill directories)"

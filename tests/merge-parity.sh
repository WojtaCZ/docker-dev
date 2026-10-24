#!/usr/bin/env bash
# Merge parity check: everything the five children shipped must exist in the
# unified repo/image. Driven by tests/parity/manifest.txt
# (generate with tools/gen-parity-manifest.sh).
#
#   bash tests/merge-parity.sh repo     # on the host, from the repo root
#   bash tests/merge-parity.sh image    # INSIDE the built image:
#     docker run --rm -v "$PWD/tests:/tests:ro" <image> bash /tests/merge-parity.sh image
#
# Prints "MISSING kind|name" per gap; exits 1 if there is any.

set -uo pipefail

MODE="${1:-}"
case "$MODE" in repo | image) ;; *) echo "usage: $0 repo|image" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${PARITY_MANIFEST:-$HERE/parity/manifest.txt}"
ROOT="${PARITY_ROOT:-$(cd "$HERE/.." && pwd)}"
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 2; }

missing=0
checked=0

gap() { echo "MISSING $1|$2"; missing=$((missing + 1)); }

exists_skill() { [ -e "$1/$2" ] || [ -e "$1/$2.md" ]; }

repo_has_file() {
    [ -n "$(find "$ROOT" \( -name .git -o -name .superpowers \) -prune -o \
                 -name "$1" -print -quit 2>/dev/null)" ]
}

while IFS='|' read -r kind name _detail; do
    [ -n "$kind" ] || continue
    if [ "$MODE" = repo ]; then
        case "$kind" in
            file)    repo_has_file "$name" || gap "$kind" "$name" ;;
            skill)   exists_skill "$ROOT/claude-baseline/skills" "$name" || gap "$kind" "$name" ;;
            command) [ -e "$ROOT/claude-baseline/commands/$name.md" ] || gap "$kind" "$name" ;;
            doctor)  [ -e "$ROOT/dev-doctor-checks/$name" ] || gap "$kind" "$name" ;;
            udev)    [ -e "$ROOT/embedded/udev-rules/$name" ] || gap "$kind" "$name" ;;
            mcp)     python3 -c '
import json, sys
sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get("mcpServers", {}) else 1)
' "$ROOT/claude-baseline/settings.json" "$name" 2>/dev/null || gap "$kind" "$name" ;;
            *) continue ;;
        esac
    else
        case "$kind" in
            pkg)     pacman -Qq "$name" >/dev/null 2>&1 || gap "$kind" "$name" ;;
            bin)     command -v "$name" >/dev/null 2>&1 || gap "$kind" "$name" ;;
            dir)     [ -d "$name" ] || gap "$kind" "$name" ;;
            env)     [ -n "$(printenv "$name" 2>/dev/null)" ] || gap "$kind" "$name" ;;
            skill)   exists_skill "$HOME/.claude/skills" "$name" || gap "$kind" "$name" ;;
            command) [ -e "$HOME/.claude/commands/$name.md" ] || gap "$kind" "$name" ;;
            doctor)  [ -e "/opt/dev-doctor/checks.d/$name" ] || gap "$kind" "$name" ;;
            udev)    [ -e "/opt/embedded/udev-rules/$name" ] || gap "$kind" "$name" ;;
            mcp)     jq -e --arg s "$name" '.mcpServers | has($s)' \
                        "$HOME/.claude/settings.json" >/dev/null 2>&1 || gap "$kind" "$name" ;;
            file)    continue ;;
            *)       continue ;;
        esac
    fi
    checked=$((checked + 1))
done <"$MANIFEST"

if [ "$missing" -gt 0 ]; then
    echo "parity ($MODE): $missing missing of $((checked)) checked" >&2
    exit 1
fi
echo "parity ($MODE): all $checked checked entries present"

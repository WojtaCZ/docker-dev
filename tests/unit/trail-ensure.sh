#!/usr/bin/env bash
# trail-ensure: deterministic Trail-Code setup per project. Uses a stub `trail` that
# logs its arguments. Run: bash tests/run-unit.sh tests/unit/trail-ensure.sh
set -uo pipefail

ENSURE="${ENSURE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/trail-ensure.sh}"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok  $1"; else echo "FAIL: $1: expected [$2] got [$3]" >&2; fails=$((fails + 1)); fi; }

mkdir -p "$T/bin"
cat > "$T/bin/trail" <<'STUB'
#!/bin/sh
echo "$PWD|$*" >> "$TRAIL_LOG"
[ -n "${TRAIL_STUB_TOUCH:-}" ] && echo '{}' >> "$PWD/$TRAIL_STUB_TOUCH"
[ -n "${TRAIL_STUB_FAIL:-}" ] && exit 1
exit 0
STUB
chmod +x "$T/bin/trail"
export PATH="$T/bin:$PATH" TRAIL_LOG="$T/log"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

mkrepo() { git init -q "$1" && (cd "$1" && echo a > a && git add a && git commit -qm init); }
run() { : > "$TRAIL_LOG"; OUT="$("$ENSURE" "$@" 2>&1)"; RC=$?; LOG="$(sed "s|$T/||" "$TRAIL_LOG" | tr '\n' ';')"; }
oneline() { [ "$(printf '%s\n' "$OUT" | wc -l)" = 1 ]; }

mkrepo "$T/plain"
run "$T/plain"
check "plain repo -> init" "plain|init --agents claude --yes;" "$LOG"
check "exit 0" 0 "$RC"; oneline || { echo "FAIL: not exactly one output line: $OUT" >&2; fails=$((fails+1)); }

mkrepo "$T/has"; mkdir "$T/has/.trail"
run "$T/has"
check ".trail present -> build" "has|build;" "$LOG"

mkrepo "$T/optout"; touch "$T/optout/.no-trail"
run "$T/optout"; check ".no-trail -> nothing" "" "$LOG"; check ".no-trail exit 0" 0 "$RC"
mkrepo "$T/envout"
: > "$TRAIL_LOG"; DEV_TRAIL=0 "$ENSURE" "$T/envout" >/dev/null 2>&1; check "DEV_TRAIL=0 -> nothing" "" "$(cat "$TRAIL_LOG")"

mkdir "$T/notgit"; run "$T/notgit"; check "non-git dir -> nothing" "" "$LOG"
HOME="$T/home"; mkdir -p "$HOME"; run "$HOME"; check "\$HOME -> nothing" "" "$LOG"
run /; check "/ -> nothing" "" "$LOG"; check "/ exit 0" 0 "$RC"

mkrepo "$T/subsrc"; mkrepo "$T/super"; mkdir "$T/super/.trail"
(cd "$T/super" && git -c protocol.file.allow=always submodule add -q "$T/subsrc" deps/sub && git commit -qm sub)
run "$T/super"; check "submodules -> follow-submodules" "super|build --follow-submodules;" "$LOG"

mkrepo "$T/nest"; mkdir "$T/nest/.trail"; mkrepo "$T/nest/external/dep"
run "$T/nest"; check "nested repos -> follow-nested-repos" "nest|build --follow-nested-repos;" "$LOG"

mkdir "$T/many"; mkrepo "$T/many/r1"; mkrepo "$T/many/r2"; mkdir "$T/many/r2/.trail"
run "$T/many"
check "folder of repos -> build at parent + init in child without .trail" \
    "many|build;many/r1|init --agents claude --yes;" "$LOG"

mkrepo "$T/failing"
: > "$TRAIL_LOG"; OUT="$(TRAIL_STUB_FAIL=1 "$ENSURE" "$T/failing" 2>&1)"; RC=$?
check "trail failure -> still exit 0" 0 "$RC"
oneline || { echo "FAIL: failure output not one line: $OUT" >&2; fails=$((fails+1)); }

git init -q "$T/nocommit"; run "$T/nocommit"; check "no commits -> init, exit 0" "nocommit|init --agents claude --yes;" "$LOG"; check "no commits rc" 0 "$RC"
mkrepo "$T/detached"; (cd "$T/detached" && git checkout -q --detach)
run "$T/detached"; check "detached HEAD rc" 0 "$RC"

mkrepo "$T/ro"; chmod -R a-w "$T/ro"
run "$T/ro"; check "read-only workspace rc" 0 "$RC"; chmod -R u+w "$T/ro"

mkrepo "$T/mcp"; echo '{}' > "$T/mcp/.mcp.json"; (cd "$T/mcp" && git add .mcp.json && git commit -qm mcp)
head_before="$(git -C "$T/mcp" rev-parse HEAD)"
: > "$TRAIL_LOG"; OUT="$(TRAIL_STUB_TOUCH=.mcp.json "$ENSURE" "$T/mcp" 2>&1)"; RC=$?
check "HEAD unchanged (never commits)" "$head_before" "$(git -C "$T/mcp" rev-parse HEAD)"
case "$OUT" in *".mcp.json"*) check "reports changed pre-existing file" ok ok ;; *) check "reports changed pre-existing file" "mentions .mcp.json" "$OUT" ;; esac
check "nothing staged" "" "$(git -C "$T/mcp" diff --cached --name-only)"

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "trail-ensure: all passed"

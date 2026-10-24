#!/usr/bin/env bash
# dev-attach.sh, its udev template, the host udev installer and the PowerShell
# launcher. Uses a stub `docker`. Needs sudo+mknod (the throwaway test container has both).
# Run: bash tests/run-unit.sh tests/unit/dev-attach.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)"; NODE=/dev/ttyUSB7
trap 'sudo rm -f "$NODE" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok  $1"; else echo "FAIL: $1: expected [$2] got [$3]" >&2; fails=$((fails + 1)); fi; }

mkdir -p "$T/bin"
cat > "$T/bin/docker" <<'STUB'
#!/bin/sh
echo "$*" >> "$DOCKER_LOG"
[ "$1" = inspect ] && echo "${STUB_RUNNING:-true}"
exit 0
STUB
chmod +x "$T/bin/docker"
export PATH="$T/bin:$PATH" DOCKER_LOG="$T/log"
A="$ROOT/scripts/dev-attach.sh"

sudo mknod -m 660 "$NODE" c 1 3 || { echo "FAIL: cannot create fake $NODE (sudo mknod)" >&2; exit 1; }
read -r mode gid < <(stat -c '%a %g' "$NODE")

: > "$DOCKER_LOG"; out="$("$A" attach "$NODE" 2>&1)"; rc=$?
check "attach rc" 0 "$rc"
grep -q "^exec -u root dev sh -c .* _ $NODE $mode 1 3 $gid\$" "$DOCKER_LOG" \
    && check "attach issues mknod into default container 'dev' with major/minor/mode/gid" ok ok \
    || check "attach issues mknod into default container 'dev'" "exec -u root dev ... _ $NODE $mode 1 3 $gid" "$(cat "$DOCKER_LOG")"

: > "$DOCKER_LOG"; DEV_CONTAINER=other "$A" attach "$NODE" >/dev/null 2>&1
grep -q "^exec -u root other " "$DOCKER_LOG" && check "DEV_CONTAINER overrides" ok ok || check "DEV_CONTAINER overrides" "exec -u root other" "$(cat "$DOCKER_LOG")"

: > "$DOCKER_LOG"; "$A" detach "$NODE" >/dev/null 2>&1
grep -q "^exec -u root dev rm -f $NODE\$" "$DOCKER_LOG" && check "detach removes node" ok ok || check "detach removes node" "exec -u root dev rm -f $NODE" "$(cat "$DOCKER_LOG")"

out="$("$A" attach /dev/null 2>&1)"; case "$out" in skip:*) check "non-matching node skipped" ok ok ;; *) check "non-matching node skipped" "skip:" "$out" ;; esac

: > "$DOCKER_LOG"; out="$(STUB_RUNNING=false "$A" attach "$NODE" 2>&1)"; rc=$?
check "container not running -> rc 0" 0 "$rc"
case "$out" in info:*) check "container not running -> info" ok ok ;; *) check "container not running -> info" "info:" "$out" ;; esac
check "container not running -> no exec" 0 "$(grep -c '^exec' "$DOCKER_LOG")"

rules="$ROOT/embedded/udev-rules/90-dev-emb-attach.rules.in"
check "udev template handles ttyUSB add+remove" 2 "$(grep -c 'ttyUSB\[0-9\]\*' "$rules")"
check "udev template still handles ttyACM and hidraw" 4 "$(grep -c 'ttyACM\[0-9\]\*\|hidraw\[0-9\]\*' "$rules")"

grep -q '\.\./embedded/udev-rules' "$ROOT/scripts/install-host-udev-rules.sh" \
    && check "host installer finds rules in the repo layout" ok ok \
    || check "host installer finds rules in the repo layout" "mentions embedded/udev-rules" "no"

# PowerShell launcher forwards every documented dev-up.sh switch (WSL shim).
missing=""
# (DEV_PRINT is a test aid, not a user switch.)
for v in $(sed -n '/^# Env vars:/,/^# Test hooks/{/^# Test hooks/!p}' "$ROOT/scripts/dev-up.sh" | grep -o 'DEV_[A-Z_]*' | sort -u | grep -vx DEV_PRINT); do
    grep -q "$v" "$ROOT/scripts/dev-up.ps1" || missing="$missing $v"
done
check "dev-up.ps1 forwards every documented DEV_ switch" "" "${missing# }"
if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command '[void][scriptblock]::Create((Get-Content -Raw scripts/dev-up.ps1))' 2>/dev/null \
        && check "dev-up.ps1 parses" ok ok || check "dev-up.ps1 parses" ok "parse error"
fi

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "dev-attach: all passed"

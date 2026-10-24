#!/usr/bin/env bash
# Smoke test for docker-dev-embedded-telink. Runs INSIDE the built image.
#
# The Telink SDK is EULA-restricted and cannot be in CI, so this cannot
# cross-compile. What it CAN prove is that the image builds at all (the previous
# Dockerfile referenced four packages that do not exist), that the 32-bit
# runtime the tc32 blob needs is present, and that the SDK-absent path fails
# with a clear message instead of a confusing one.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

echo "== tooling =="
for b in gdb openocd probe-rs cmake ninja make meson jq \
         picocom minicom screen socat dfu-util mcu dev-doctor; do
    command -v "$b" >/dev/null || fail "missing: $b"
    pass "$b"
done

echo "== gdb is genuinely multiarch =="
gdb --batch -ex 'set architecture arm' >/dev/null 2>&1 || fail "gdb rejects arm"
pass "gdb accepts arm"

echo "== no leftover AUR build user =="
! id aurbuild >/dev/null 2>&1 || fail "aurbuild user still present"
[ ! -f /etc/sudoers.d/aurbuild ] || fail "/etc/sudoers.d/aurbuild still present"
pass "clean"

echo "== 32-bit runtime for the tc32 blob =="
ls /usr/lib32/libc.so.6 >/dev/null 2>&1 || fail "no 32-bit glibc — the tc32 toolchain cannot run"
pass "lib32-glibc present"

echo "== SDK mount point =="
[ -d /opt/telink ] || fail "/opt/telink missing"
[ "$(stat -c %U /opt/telink)" = "dev" ] || fail "/opt/telink not owned by dev"
pass "/opt/telink ready for the SDK bind mount"
case ":$PATH:" in
    *":/opt/telink/sdk/tools/tc32/bin:"*) pass "tc32 bin dir on PATH" ;;
    *) fail "tc32 bin dir not on PATH" ;;
esac

echo "== shared assets (copies owned by docker-dev-embedded-base) =="
for f in /opt/embedded/run-profile-task.sh \
         /opt/embedded/profile.schema.json \
         /opt/embedded/vscode-templates/tasks.json \
         /opt/embedded/vscode-templates/launch.json \
         /opt/embedded/cmake/embedded-common.cmake \
         /opt/embedded/cmake/host-test.cmake; do
    [ -f "$f" ] || fail "missing $f"
    case "$f" in *.json) jq -e . "$f" >/dev/null || fail "$f invalid JSON";; esac
    pass "$(basename "$f")"
done

echo "== settings layer =="
S="$HOME/.claude/settings.json"
for server in github git context7 sequential-thinking fetch; do
    jq -e --arg s "$server" '.mcpServers | has($s)' "$S" >/dev/null || fail "MCP $server missing"
done
# This leaf bypasses embedded-base, so it declares `fetch` itself.
[ "$(jq -r '.mcpServers.fetch.command' "$S")" = "uvx" ] || fail "fetch MCP must use uvx"
pass "baseline + telink layers merged"

echo "== claude assets =="
for s in tlsr8258-ble-stack tlsr-otp-vs-flash; do
    { [ -f "$HOME/.claude/skills/$s.md" ] || [ -f "$HOME/.claude/skills/$s/SKILL.md" ]; } || fail "skill $s.md not installed"
    pass "skill: $s"
done
[ -f "$HOME/.claude/commands/telink-sdk-check.md" ] || fail "/telink-sdk-check missing"
pass "command: /telink-sdk-check"

echo "== SDK-absent path fails clearly, not confusingly =="
work=$(mktemp -d); cd "$work"
cp /opt/embedded/profiles/telink.json .mcu-profile.json
mcu --list >/dev/null || fail "mcu --list broke on the shipped profile"
pass "mcu --list parses the shipped profile"

out=$(mcu build 2>&1 || true)
grep -qi 'Telink SDK not mounted' <<< "$out" \
    || fail "build without an SDK did not say so clearly. Got: $out"
pass "build without an SDK reports the real reason"

# Placeholder tasks must FAIL rather than echo and report success — a Flash
# task that silently does nothing is worse than one that errors.
if mcu debugServer >/dev/null 2>&1; then
    fail "debugServer returned success while doing nothing"
fi
pass "unsupported tasks exit non-zero"

cd /; rm -rf "$work"

echo "== dev-doctor =="
dev-doctor
dev-doctor --json | jq -e '.ok == true' >/dev/null || fail "dev-doctor reported failures"
pass "dev-doctor clean (SDK absence is a warning, not a failure)"

echo
echo "section 40-telink passed"

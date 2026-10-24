#!/usr/bin/env bash
# dev-doctor checks contributed by docker-dev-embedded-telink.
set -uo pipefail

emit() { echo "$1|$2|$3"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Shared tooling (this leaf bypasses embedded-base, so it must assert its own)
for b in gdb openocd probe-rs cmake ninja make jq picocom minicom screen socat mcu; do
    if have "$b"; then
        emit OK "$b" "$(command -v "$b")"
    else
        emit FAIL "$b" "not found on PATH"
    fi
done

if have gdb; then
    if gdb --batch -ex 'set architecture arm' >/dev/null 2>&1; then
        emit OK "gdb-multiarch" "arm architecture accepted"
    else
        emit FAIL "gdb-multiarch" "gdb not built --enable-targets=all"
    fi
fi

# 32-bit runtime — without it the tc32 blob cannot execute at all
if [ -e /usr/lib32/libc.so.6 ] || ldconfig -p 2>/dev/null | grep -q 'libc.so.6 (libc6)'; then
    emit OK "lib32" "32-bit glibc present (tc32 blob can run)"
else
    emit FAIL "lib32" "no 32-bit glibc — the tc32 toolchain will not execute"
fi

# The SDK is host-mounted, so its absence is expected in CI: warn, do not fail.
SDK="${SDK:-/opt/telink/sdk}"
if [ -x "$SDK/tools/tc32/bin/tc32-elf-gcc" ]; then
    emit OK "telink-sdk" "$SDK mounted; tc32-elf-gcc present"
    if "$SDK/tools/tc32/bin/tc32-elf-gcc" --version >/dev/null 2>&1; then
        emit OK "tc32-runs" "$("$SDK/tools/tc32/bin/tc32-elf-gcc" --version 2>&1 | head -1)"
    else
        emit FAIL "tc32-runs" "tc32-elf-gcc present but will not execute (missing 32-bit libs?)"
    fi
elif [ -d "$SDK" ] && [ -n "$(ls -A "$SDK" 2>/dev/null)" ]; then
    emit FAIL "telink-sdk" "$SDK is mounted but has no tools/tc32/bin/tc32-elf-gcc — wrong directory?"
else
    emit WARN "telink-sdk" "not mounted. Nothing can be compiled. Mount with: -v ~/telink/Telink_825X_SDK:$SDK:ro"
fi

# Community SWS flashing tools
TT="${TLSR_TOOLS:-/opt/telink/tlsr-tools}"
if [ -f "$TT/TlsrPgm.py" ]; then
    emit OK "tlsr-tools" "$TT"
else
    emit WARN "tlsr-tools" "$TT has no TlsrPgm.py — in-container flashing unavailable, use Telink BDT on the host"
fi

# Shared assets copied from docker-dev-embedded-base
for f in /opt/embedded/vscode-templates/tasks.json \
         /opt/embedded/vscode-templates/launch.json \
         /opt/embedded/profile.schema.json \
         /opt/embedded/cmake/host-test.cmake; do
    if [ -f "$f" ]; then
        emit OK "shared:$(basename "$f")" "present"
    else
        emit FAIL "shared:$(basename "$f")" "missing — resync from docker-dev-embedded-base"
    fi
done

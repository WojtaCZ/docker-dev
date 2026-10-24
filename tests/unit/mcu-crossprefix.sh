#!/usr/bin/env bash
# `mcu` resolves the profile upward and sets CROSS_PREFIX per project.
# Runs inside a container with jq: bash tests/run-unit.sh tests/unit/mcu-crossprefix.sh
set -uo pipefail

MCU="${MCU:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/embedded/run-profile-task.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
check() { # name expected actual
    if [ "$2" = "$3" ]; then echo "  ok  $1"; else echo "FAIL: $1: expected [$2] got [$3]" >&2; fails=$((fails + 1)); fi
}
profile() { # dir json
    mkdir -p "$1"; printf '%s\n' "$2" > "$1/.mcu-profile.json"
}
prefix_in() { # dir  -> prints what `mcu build` saw
    (cd "$1" && bash "$MCU" build 2>&1)
}

profile "$T/explicit" '{"crossPrefix":"foo-","core":"cortex-m4","build":"echo P=[$CROSS_PREFIX]"}'
check "explicit crossPrefix wins" "P=[foo-]" "$(prefix_in "$T/explicit")"

profile "$T/arm" '{"core":"cortex-m33","build":"echo P=[$CROSS_PREFIX]"}'
check "derive arm from core" "P=[arm-none-eabi-]" "$(prefix_in "$T/arm")"

profile "$T/rv" '{"core":"rv32ec","build":"echo P=[$CROSS_PREFIX]"}'
check "derive riscv from core" "P=[riscv-none-elf-]" "$(prefix_in "$T/rv")"

profile "$T/tc" '{"core":"tc32","build":"echo P=[$CROSS_PREFIX]"}'
check "derive tc32 from core" "P=[tc32-elf-]" "$(prefix_in "$T/tc")"

profile "$T/root/fw" '{"core":"cortex-m0plus","build":"echo P=[$CROSS_PREFIX] D=$(basename $PWD)"}'
mkdir -p "$T/root/fw/sub/dir"
check "nearest profile found upward, runs in its directory" \
    "P=[arm-none-eabi-] D=fw" "$(prefix_in "$T/root/fw/sub/dir")"

profile "$T/mix/fw-arm" '{"core":"cortex-m4","build":"echo P=[$CROSS_PREFIX]"}'
profile "$T/mix/fw-wch" '{"core":"rv32imac","build":"echo P=[$CROSS_PREFIX]"}'
mkdir -p "$T/mix/fw-arm/src" "$T/mix/fw-wch/src"
check "mixed repo: arm component" "P=[arm-none-eabi-]" "$(prefix_in "$T/mix/fw-arm/src")"
check "mixed repo: wch component" "P=[riscv-none-elf-]" "$(prefix_in "$T/mix/fw-wch/src")"

out="$(cd "$T/arm" && CROSS_PREFIX=zzz- bash "$MCU" build 2>&1)"
check "inherited CROSS_PREFIX is overridden" "P=[arm-none-eabi-]" "$out"

check "mcu --cross-prefix prints the project's prefix" "arm-none-eabi-" "$(cd "$T/root/fw/sub/dir" && bash "$MCU" --cross-prefix 2>&1)"
check "mcu --cross-prefix in a riscv component" "riscv-none-elf-" "$(cd "$T/mix/fw-wch/src" && bash "$MCU" --cross-prefix 2>&1)"

mkdir -p "$T/empty/deeper"
out="$(cd "$T/empty/deeper" && bash "$MCU" build 2>&1)"; rc=$?
check "no profile anywhere exits 1" "1" "$rc"
case "$out" in *".mcu-profile.json not found"*) check "no-profile message" ok ok ;;
    *) check "no-profile message" "mentions .mcu-profile.json not found" "$out" ;; esac

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "mcu-crossprefix: all passed"

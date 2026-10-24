#!/usr/bin/env bash
# dev-doctor checks contributed by docker-dev-embedded-wch.
set -uo pipefail

emit() { echo "$1|$2|$3"; }
have() { command -v "$1" >/dev/null 2>&1; }

for t in gcc g++ gdb objcopy objdump nm size readelf ar; do
    if have "riscv-none-elf-${t}"; then
        emit OK "riscv:${t}" "$(command -v "riscv-none-elf-${t}")"
    else
        emit FAIL "riscv:${t}" "riscv-none-elf-${t} not on PATH"
    fi
done

if have riscv-none-elf-gcc; then
    emit OK "riscv-gcc-version" "$(riscv-none-elf-gcc -dumpversion)"
    # RV32EC (CH32V003) needs the ilp32e multilib; without it the V003 will not link.
    if riscv-none-elf-gcc -print-multi-lib 2>/dev/null | grep -q 'rv32e'; then
        emit OK "newlib-rv32e" "rv32e multilib present (CH32V003 OK)"
    else
        emit FAIL "newlib-rv32e" "no rv32e multilib — CH32V003 will not link"
    fi
    # xPack's default multilib IS rv32imac/ilp32, so -march=rv32imac resolves to
    # "." rather than to a named entry in -print-multi-lib (grepping that list
    # for 'rv32imac' always missed it). Ask gcc what it actually selects.
    if riscv-none-elf-gcc -Q --help=target 2>/dev/null | grep -E -- '-march=' | grep -q 'rv32imac' \
       && [ "$(riscv-none-elf-gcc -march=rv32imac -mabi=ilp32 -print-multi-directory 2>/dev/null)" = "." ]; then
        emit OK "newlib-rv32imac" "default multilib is rv32imac/ilp32 (CH58x/V103/V203/X033 OK)"
    else
        emit WARN "newlib-rv32imac" "-march=rv32imac does not resolve to the default multilib"
    fi
fi

# Flash tools. wlink was previously assumed to come from the base image via a
# non-existent AUR package; it is installed here now, so assert it.
if have wlink; then
    emit OK "wlink" "$(wlink --version 2>&1 | head -1)"
else
    emit FAIL "wlink" "not installed — flash/erase/reset would all fail"
fi
if have wchisp; then
    emit OK "wchisp" "probe-free USB bootloader flashing available"
else
    emit WARN "wchisp" "not installed — no probe-free flash path"
fi

# ch32fun scaffolding
CH="${CH32FUN_ROOT:-/opt/ch32fun}"
if [ -n "${CH32FUN:-}" ]; then
    emit WARN "ch32fun-env" "CH32FUN is set ($CH32FUN) — ch32fun.mk reads it as its own ch32fun/ dir and will break; unset it"
fi
if [ -f "$CH/ch32fun/ch32fun.c" ]; then
    emit OK "ch32fun" "$CH"
elif [ -d "$CH" ]; then
    emit WARN "ch32fun" "$CH present but ch32fun/ch32fun.c not found — layout changed upstream?"
else
    emit FAIL "ch32fun" "$CH missing"
fi

if [ -f /opt/embedded/cmake/toolchains/riscv-none-elf.cmake ]; then
    emit OK "riscv-toolchain-cmake" "/opt/embedded/cmake/toolchains/riscv-none-elf.cmake"
else
    emit FAIL "riscv-toolchain-cmake" "missing"
fi

# CH58x USB ISP path: SDK fetcher and profile
have ch58x-sdk && emit OK "ch58x-sdk" "on-demand EVT SDK fetcher" || emit WARN "ch58x-sdk" "missing"
[ -f /opt/embedded/profiles/ch582f.json ] && emit OK "ch582f-profile" "/opt/embedded/profiles/ch582f.json" \
    || emit WARN "ch582f-profile" "missing"
# A chip sitting in its USB boot ROM (4348:55e0), absent in CI so warn only
if have lsusb; then
    if lsusb 2>/dev/null | grep -qi '\(4348\|1a86\):55e0'; then
        emit OK "wch-isp" "$(lsusb | grep -i ':55e0' | head -1)"
    else
        emit WARN "wch-isp" "no chip in USB boot ROM (4348:55e0) — hold BOOT while plugging in; in WSL: usbipd attach --wsl --auto-attach --hardware-id 4348:55e0"
    fi
fi

# WCH-Link on USB (absent in CI, so warn only)
if have lsusb; then
    if lsusb 2>/dev/null | grep -qi '1a86:801'; then
        emit OK "wch-link" "$(lsusb | grep -i '1a86:801' | head -1)"
    else
        emit WARN "wch-link" "no WCH-Link (1a86:801x) on USB"
    fi
fi

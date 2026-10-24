#!/usr/bin/env bash
# Assertions that only make sense for the merged image: every toolchain coexists,
# nothing leaks a global CROSS_PREFIX, Trail is installed, parity holds.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

echo "== merge parity (image) =="
bash "$(dirname "${BASH_SOURCE[0]}")/../merge-parity.sh" image || fail "parity manifest not satisfied by the image"
pass "every manifest entry present"

echo "== no global CROSS_PREFIX =="
[ -z "${CROSS_PREFIX+x}" ] || fail "CROSS_PREFIX is set to '${CROSS_PREFIX}'; it must be per-project"
pass "CROSS_PREFIX unset"

echo "== toolchains coexist =="
work=$(mktemp -d); cd "$work"
echo 'int main(void){return 0;}' > t.c
arm-none-eabi-gcc -mcpu=cortex-m33 -mthumb -mfloat-abi=hard -mfpu=fpv5-sp-d16 \
    --specs=nosys.specs t.c -o t.elf || fail "arm Cortex-M33 hard-float link failed"
arm-none-eabi-readelf -A t.elf | grep -q 'Tag_CPU_arch: v8-M.mainline' || fail "arm output is not ARMv8-M Mainline"
pass "arm-none-eabi: Cortex-M33 hard-float links"
riscv-none-elf-gcc -march=rv32ec_zicsr -mabi=ilp32e -c t.c -o t_rv.o || fail "riscv rv32ec compile failed"
pass "riscv-none-elf: rv32ec compiles"
printf '#include <cstdio>\nint main(){std::puts("host-ok");}\n' > h.cpp
g++ -std=c++20 h.cpp -o h_gcc && [ "$(./h_gcc)" = host-ok ] || fail "host g++ failed"
clang++ -std=c++20 h.cpp -o h_clang && [ "$(./h_clang)" = host-ok ] || fail "host clang++ failed"
pass "host g++ and clang++ build and run"
cd /; rm -rf "$work"

echo "== no duplicate cross-tool basenames =="
dups=$(ls /usr/local/bin /usr/bin | grep -E '^(arm-none-eabi|riscv-none-elf|tc32-elf)-' | sort | uniq -d)
[ -z "$dups" ] || fail "duplicate cross-tool names on PATH: $dups"
pass "cross-tool names unique"

echo "== web + php + multilib =="
modules=$(php -m)
for m in gd intl pdo_sqlite sqlite3; do grep -qi "^$m\$" <<< "$modules" || fail "php module $m not loaded"; done
pass "php gd/intl/pdo_sqlite/sqlite3 loaded"
web --schema | jq -e '.title' >/dev/null || fail "web --schema broken"
pass "web --schema"
pacman -Qq lib32-glibc >/dev/null || fail "lib32-glibc missing (tc32 needs it)"
[ "$(stat -c %U /opt/telink)" = dev ] || fail "/opt/telink not owned by dev"
pass "lib32-glibc present, /opt/telink owned by dev"

echo "== trail =="
trail --version >/dev/null || fail "trail not installed"
pass "trail $(trail --version | head -1)"
out=$(trail telemetry status 2>&1 || true)
grep -qi 'disabled\|off' <<< "$out" || fail "trail telemetry is not disabled: $out"
pass "trail telemetry disabled"

echo "section 60-unified passed"

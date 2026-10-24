#!/usr/bin/env bash
# Generate the merge-parity manifest from the REAL child repos.
#
#   tools/gen-parity-manifest.sh <children-dir> > tests/parity/manifest.txt
#
# <children-dir> holds docker-dev-{embedded-base,embedded-arm,embedded-telink,
# embedded-wch,web}. Line format: kind|name|detail
#   kinds: pkg bin dir env file skill command doctor udev mcp
#
# Sources of truth:
#   * the five child checkouts under <children-dir>
#   * the arm leaf's Dockerfile is taken from ARM_LOCAL (default
#     ~/Documents/docker-dev-embedded-arm) when present, because that checkout
#     carries uncommitted work (bluez-utils) that is not on GitHub
#   * the template's own baseline is read from the `main` branch, so the
#     manifest does not change as this branch rewrites the template
#
# Rerunning must give identical output (sorted, de-duplicated).

set -euo pipefail

CHILDREN="${1:?usage: gen-parity-manifest.sh <children-dir>}"
ARM_LOCAL="${ARM_LOCAL:-$HOME/Documents/docker-dev-embedded-arm}"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEAVES=(embedded-base embedded-arm embedded-telink embedded-wch web)

# Dockerfile text for a leaf, comments stripped and continuation lines joined.
dockerfile() {
    local leaf="$1" f="$CHILDREN/docker-dev-$1/Dockerfile"
    if [ "$leaf" = embedded-arm ] && [ -f "$ARM_LOCAL/Dockerfile" ]; then
        f="$ARM_LOCAL/Dockerfile"
    fi
    grep -v '^[[:space:]]*#' "$f" | sed -e ':a' -e '/\\$/N; s/\\\n//; ta'
}
template_dockerfile() {
    git -C "$TEMPLATE_DIR" show main:Dockerfile \
        | grep -v '^[[:space:]]*#' | sed -e ':a' -e '/\\$/N; s/\\\n//; ta'
}

emit_pkgs() {
    # Split each logical line on '&&'; any segment that is a `pacman -S...`
    # contributes its non-flag tokens (flag-only segments such as -Syu add none).
    awk '
        {
            n = split($0, seg, /&&/)
            for (i = 1; i <= n; i++) {
                s = seg[i]; sub(/^[ \t]*(RUN[ \t]+)?/, "", s)
                if (s !~ /^pacman[ \t]+-S/) continue
                m = split(s, tok, /[ \t]+/)
                for (j = 2; j <= m; j++) {
                    t = tok[j]
                    if (t == "" || t ~ /^-/ || t == "\\") continue
                    print "pkg|" t "|"
                }
            }
        }'
}

emit_env() {
    awk '
        /^ENV[ \t]/ {
            line = $0; sub(/^ENV[ \t]+/, "", line)
            n = split(line, tok, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                if (tok[i] !~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
                name = tok[i]; sub(/=.*/, "", name)
                if (name == "CROSS_PREFIX" || name == "PATH" || name == "LANG") continue
                print "env|" name "|"
            }
        }'
}

{
    template_dockerfile | emit_pkgs
    for leaf in "${LEAVES[@]}"; do
        dockerfile "$leaf" | emit_pkgs
        dockerfile "$leaf" | emit_env

        d="$CHILDREN/docker-dev-$leaf"
        for p in "$d"/claude-*/skills/*; do
            [ -e "$p" ] || continue
            b="$(basename "$p")"; echo "skill|${b%.md}|"
        done
        for p in "$d"/claude-*/commands/*.md; do
            [ -e "$p" ] || continue
            b="$(basename "$p")"; echo "command|${b%.md}|"
        done
        for p in "$d"/dev-doctor-checks/*; do
            [ -e "$p" ] || continue; echo "doctor|$(basename "$p")|"
        done
        for p in "$d"/udev-rules/*; do
            [ -e "$p" ] || continue; echo "udev|$(basename "$p")|"
        done
        for p in "$d"/claude-*/settings.layer.json; do
            [ -e "$p" ] || continue
            python3 - "$p" <<'PY'
import json, sys
for k in json.load(open(sys.argv[1])).get("mcpServers", {}):
    print(f"mcp|{k}|")
PY
        done
    done

    git -C "$TEMPLATE_DIR" show main:claude-baseline/settings.json | python3 -c '
import json, sys
for k in json.load(sys.stdin).get("mcpServers", {}):
    print(f"mcp|{k}|")'

    # Files that must exist somewhere in the repo (matched by basename).
    for f in run-profile-task.sh profile.schema.json svd-find.sh \
             install-host-udev-rules.sh dev-attach.sh ch58x-sdk.sh \
             build-cmsis-dsp.sh web-post-create.sh run-web-task.sh \
             web-profile.schema.json embedded-common.cmake host-test.cmake \
             arm-none-eabi.cmake riscv-none-elf.cmake launch.json tasks.json \
             ch582f.json docker-compose.yml; do
        echo "file|$f|"
    done

    # Binaries and directories the built image must provide.
    for b in wlink wchisp riscv-none-elf-gcc arm-none-eabi-gcc arm-none-eabi-gdb \
             openocd probe-rs pyocd st-info sigrok-cli bluetoothctl php composer \
             deno bun chromium nginx mcu web svd-find build-cmsis-dsp ch58x-sdk \
             trail trail-ensure work-notes dev-attach clang cmake ninja gdb; do
        echo "bin|$b|"
    done
    for dir in /opt/cmsis /opt/cmsis-dsp /opt/svd /opt/st/cmsis /opt/riscv \
               /opt/ch32fun /opt/telink /opt/embedded /opt/web; do
        echo "dir|$dir|"
    done
} | LC_ALL=C sort -u

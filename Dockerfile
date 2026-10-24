# syntax=docker/dockerfile:1.7
#
# Unified dev container: baseline + embedded (ARM Cortex-M, WCH RISC-V, Telink
# runtime) + web, with every toolchain baked in at build time. Nothing is ever
# installed or built in a running container.
#
# Layer order is deliberate: the slow, rarely-changing layers (packages, upstream
# clones, CMSIS-DSP builds) come first, and the scripts/assets that change often
# come last, so editing a script does not rebuild a toolchain.
#
# Toolchain selection is per PROJECT (`crossPrefix` in .mcu-profile.json, read by
# `mcu`), so there is deliberately no container-wide CROSS_PREFIX variable.
FROM archlinux:latest

ARG USER_NAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# Pinned upstream revisions. Bumping one shows up in the diff instead of
# silently changing what the image contains between two builds of the same tag.
ARG CMSIS_SVD_REF=main
ARG SVD_STM32_REF=main
ARG CMSIS_6_REF=v6.2.0
ARG CMSIS_DSP_REF=v1.17.0
ARG RISCV_GCC_VERSION=15.2.0-1
ARG WLINK_VERSION=v0.1.2
# `nightly` on purpose: v0.3.0 (2024-10) predates `wchisp config enable-debug` and
# the CH582F/CH573F/CH592F WeAct boards; there has been no tagged release since.
# Pin to a tag via --build-arg WCHISP_VERSION=vX.Y.Z when one appears.
ARG WCHISP_VERSION=nightly
ARG CH32FUN_REF=master
ARG TLSR_TOOLS_REF=main
ARG TRAIL_VERSION=0.25.0

# Which ST CMSIS device families to bake in. All Apache-2.0, headers + startup +
# GCC linker templates only, NOT the HAL. ~32 MB for the full set.
ARG ST_FAMILIES="wba f0 f1 f3 f4 f7 g0 g4 l0 l4 l5 u5 h5 h7 wb wl"
# Which Cortex-M variants to prebuild CMSIS-DSP for.
ARG DSP_CORES="cortex-m0plus cortex-m3 cortex-m4f cortex-m7f cortex-m33f"

# ===========================================================================
# 1. Baseline
# ===========================================================================

# Rebuild the pacman trust database. The stock image ships /etc/pacman.d/gnupg
# WITHOUT a local signing key, so every Arch developer key sits at [marginal]
# trust and any package they sign is rejected with "invalid or corrupted package
# (PGP signature)". --init regenerates that key; --populate then locally signs
# the master keys so developer keys resolve to [full].
RUN pacman-key --init && pacman-key --populate archlinux

# [multilib] is enabled once, here, for the 32-bit tc32 (Telink) compiler blob.
# A single pacman call per group avoids partial-upgrade issues on a rolling distro.
# util-linux (setpriv) is what entrypoint.sh uses to drop privileges after an
# optional UID/GID remap.
RUN sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        base-devel git openssh sudo \
        nodejs npm python uv \
        which less man-db unzip zip \
        curl wget jq github-cli \
        util-linux \
    && pacman -Scc --noconfirm

# Non-root user with passwordless sudo (the container is already the isolation boundary)
RUN groupadd --gid ${USER_GID} ${USER_NAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME} && \
    chmod 0440 /etc/sudoers.d/${USER_NAME}

# Workspace mount targets, owned by dev. dev-up.sh mounts the project at
# /workspaces/<name>-<hash>; /workspace stays as the fallback path.
RUN mkdir -p /workspace /workspaces && chown ${USER_UID}:${USER_GID} /workspace /workspaces

# ===========================================================================
# 2. Shared embedded tooling (probe drivers, debug, analysis, serial, host tests)
#
# Arch package-name notes (all verified against the official repos):
#   * `gdb`, NOT `gdb-multiarch` (the Debian name). Arch's gdb is built
#     --enable-targets=all, so it IS the multiarch gdb.
#   * `clang` already ships clangd / clang-tidy / clang-format / clang-query.
#   * `probe-rs` is in `extra`; pyocd and tio are not (pyocd comes from PyPI
#     below; `tio` is dropped, picocom/minicom/screen/socat cover it).
# ===========================================================================
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        gdb openocd stlink probe-rs dfu-util \
        clang lld llvm cppcheck \
        cmake ninja make meson ccache dtc \
        picocom screen minicom socat \
        usbutils libusb libusb-compat hidapi \
        python-pyelftools python-pyserial \
        gtest catch2 gcovr lcov \
        rsync fakeroot patch \
    && pacman -Scc --noconfirm

# pyOCD from PyPI (not in the Arch repos). Brings cmsis-pack-manager, which is how
# you get device support and SVDs for parts newer than the current OpenOCD.
# UV_TOOL_BIN_DIR puts the launcher where every user can reach it.
ENV UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    PYOCD_HOME=/opt/pyocd
RUN uv tool install pyocd && \
    mkdir -p /opt/pyocd && chmod 0777 /opt/pyocd && \
    pyocd --version

# SVD store: register-level reasoning, the VSCode Peripheral Viewer and the
# register-decode-svd skill all need a .svd for the target. This is the
# multi-vendor set; the ARM layer below adds modm-io's STM32 mirror on top.
RUN git clone --depth=1 --branch "${CMSIS_SVD_REF}" \
        https://github.com/cmsis-svd/cmsis-svd-data /opt/svd/cmsis-svd-data && \
    rm -rf /opt/svd/cmsis-svd-data/.git
ENV SVD_STORE=/opt/svd

# Group membership so /dev/ttyACM*, /dev/ttyUSB* and probe nodes are accessible
RUN groupadd -f plugdev && groupadd -f dialout && \
    usermod -aG dialout,uucp,tty,plugdev,lock ${USER_NAME}

# ===========================================================================
# 3. ARM Cortex-M (STM32 all families incl. ARMv8-M WBA/U5/H5/L5, RP2040, MSPM0)
# ===========================================================================
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        arm-none-eabi-gcc arm-none-eabi-newlib \
        arm-none-eabi-gdb arm-none-eabi-binutils \
    && pacman -Scc --noconfirm

# Fail the build now, not at the first compile, if the multilib variant needed by
# ARMv8-M Mainline hard-float parts (STM32WBA65, U5, H5) is missing.
RUN arm-none-eabi-gcc -print-multi-lib | grep -q 'v8-m.main' || \
        (echo "FATAL: newlib has no v8-m.main multilib; Cortex-M33 targets would fail to link" && exit 1)

# Bench tooling: sigrok-cli (+fx2lafw so cheap FX2 analyzers enumerate), ALSA
# utils for USB-MIDI, and bluez-utils (bluetoothctl/btmon) which talks to the
# HOST's bluetoothd over the system D-Bus socket that dev-up.sh bind-mounts.
RUN pacman -S --noconfirm --needed \
        sigrok-cli sigrok-firmware-fx2lafw \
        alsa-utils \
        bluez-utils \
    && pacman -Scc --noconfirm

# CMSIS_6: Apache-2.0, header-only (core_cm*.h, cmsis_gcc.h, TrustZone helpers).
RUN git clone --depth=1 --branch "${CMSIS_6_REF}" \
        https://github.com/ARM-software/CMSIS_6 /opt/cmsis && \
    rm -rf /opt/cmsis/.git
ENV CMSIS_DIR=/opt/cmsis

# CMSIS-DSP, built once PER CORE (a cortex-m4 archive linked into a Cortex-M33
# image is an architecture mismatch). Layout: /opt/cmsis-dsp/lib/<core>/libCMSISDSP.a
COPY embedded/scripts/build-cmsis-dsp.sh /opt/embedded/build-cmsis-dsp.sh
RUN chmod +x /opt/embedded/build-cmsis-dsp.sh && \
    ln -sf /opt/embedded/build-cmsis-dsp.sh /usr/local/bin/build-cmsis-dsp && \
    git clone --depth=1 --branch "${CMSIS_DSP_REF}" \
        https://github.com/ARM-software/CMSIS-DSP /opt/cmsis-dsp && \
    rm -rf /opt/cmsis-dsp/.git && \
    for core in ${DSP_CORES}; do \
        /opt/embedded/build-cmsis-dsp.sh "$core" || exit 1; \
    done && \
    rm -rf /opt/cmsis-dsp/build-*
ENV CMSIS_DSP_DIR=/opt/cmsis-dsp

# ST CMSIS device components (Apache-2.0, NOT the HAL): stm32<family>xx.h, startup
# file and GCC linker template per family; for WBA also the TrustZone partition header.
RUN mkdir -p /opt/st/cmsis && \
    for fam in ${ST_FAMILIES}; do \
        echo "== cmsis-device-${fam} ==" && \
        git clone --depth=1 \
            "https://github.com/STMicroelectronics/cmsis-device-${fam}" \
            "/opt/st/cmsis/${fam}" && \
        rm -rf "/opt/st/cmsis/${fam}/.git" || exit 1; \
    done
ENV STM32_CMSIS_DIR=/opt/st/cmsis

# STM32 SVD mirror (modm-io): covers C0/G0/G4/H5/H7/L5/U5/WBA5/WB0/N6.
# WBA6x (STM32WBA65) is in neither mirror: `svd-find --pack stm32wba65` pulls it.
RUN git clone --depth=1 --branch "${SVD_STM32_REF}" \
        https://github.com/modm-io/cmsis-svd-stm32 /opt/svd/stm32 && \
    rm -rf /opt/svd/stm32/.git

# ===========================================================================
# 4. RISC-V / WCH (CH32V003 / V103 / V203 / V303 / X033, CH58x)
# Everything comes from an official prebuilt release tarball: no AUR helper.
# ===========================================================================

# xPack RISC-V GCC + newlib (RV32EC through RV32IMAC). Symlinked onto the default
# PATH so launch.json and the shared skills resolve riscv-none-elf-* directly.
RUN mkdir -p /opt/riscv && \
    curl -fsSL -o /tmp/riscv.tar.gz \
      "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${RISCV_GCC_VERSION}/xpack-riscv-none-elf-gcc-${RISCV_GCC_VERSION}-linux-x64.tar.gz" && \
    tar -xzf /tmp/riscv.tar.gz -C /opt/riscv --strip-components=1 && \
    rm /tmp/riscv.tar.gz && \
    for b in /opt/riscv/bin/riscv-none-elf-*; do \
        ln -sf "$b" "/usr/local/bin/$(basename "$b")"; \
    done && \
    riscv-none-elf-gcc --version && \
    riscv-none-elf-gdb --version

# wlink: WCH-Link flashing and debugging (also a GDB server).
RUN curl -fsSL -o /tmp/wlink.tar.gz \
      "https://github.com/ch32-rs/wlink/releases/download/${WLINK_VERSION}/wlink-${WLINK_VERSION}-linux-x64.tar.gz" && \
    tar -xzf /tmp/wlink.tar.gz -C /tmp && \
    install -m0755 "$(find /tmp -name wlink -type f | head -1)" /usr/local/bin/wlink && \
    rm -rf /tmp/wlink* && \
    wlink --version

# wchisp: USB bootloader flashing. Works with NO probe: CH32V parts expose a
# factory USB ISP bootloader.
RUN if [ "${WCHISP_VERSION}" = "nightly" ]; then \
        asset=wchisp-linux-x64.tar.gz; \
    else \
        asset="wchisp-${WCHISP_VERSION}-linux-x64.tar.gz"; \
    fi && \
    curl -fsSL -o /tmp/wchisp.tar.gz \
      "https://github.com/ch32-rs/wchisp/releases/download/${WCHISP_VERSION}/${asset}" && \
    tar -xzf /tmp/wchisp.tar.gz -C /tmp && \
    install -m0755 "$(find /tmp -name wchisp -type f | head -1)" /usr/local/bin/wchisp && \
    rm -rf /tmp/wchisp* && \
    wchisp --version && \
    wchisp config --help | grep -q enable-debug

# ch32fun (formerly ch32v003fun): community bare-metal scaffolding for the whole
# CH32V/CH32X range. NOT named CH32FUN: ch32fun.mk does `CH32FUN ?= <its own
# ch32fun/ dir>`, so exporting CH32FUN=<repo root> breaks every ch32fun build.
RUN git clone --depth=1 --branch "${CH32FUN_REF}" \
        https://github.com/cnlohr/ch32fun /opt/ch32fun && \
    rm -rf /opt/ch32fun/.git && \
    ln -sfn /opt/ch32fun /opt/ch32v003fun
ENV CH32FUN_ROOT=/opt/ch32fun \
    CH32V_FUN=/opt/ch32fun

# ===========================================================================
# 5. Telink TLSR8258 (TC32): runtime pieces only
#
# The Telink SDK is EULA-restricted and not redistributable, so the compiler is a
# host MOUNT, not baked in:  -v ~/telink/Telink_825X_SDK:/opt/telink/sdk:ro
# It carries the tc32 g++ binary blob under tools/tc32/bin/ (a 32-bit binary,
# hence lib32 below; [multilib] was enabled in layer 1).
# ===========================================================================
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed lib32-glibc lib32-gcc-libs && \
    pacman -Scc --noconfirm
RUN mkdir -p /opt/telink && chown ${USER_UID}:${USER_GID} /opt/telink

# TLSR825x SWS flashing tools (community; Telink's own BDT is Windows-GUI only).
# pvvx/TLSRPGM drives a SWire programmer over a serial port and needs dedicated
# programmer hardware wired PD3->RESET, PD4<->SWS, PB4->Power. Cloned rather than
# vendored so provenance stays visible.
RUN git clone --depth=1 --branch "${TLSR_TOOLS_REF}" \
        https://github.com/pvvx/TLSRPGM /opt/telink/tlsr-tools 2>/dev/null \
     || echo "WARN: TLSRPGM clone failed; flashing will need the host BDT" && \
    rm -rf /opt/telink/tlsr-tools/.git
ENV TLSR_TOOLS=/opt/telink/tlsr-tools

# ===========================================================================
# 6. Web (PHP, JS runtimes, DB clients, nginx, chromium for Playwright)
# ===========================================================================
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        php php-fpm php-sqlite php-intl php-gd \
        composer \
        mariadb-clients postgresql-libs sqlite redis \
        nginx deno chromium \
    && pacman -Scc --noconfirm

# Arch ships these extensions disabled in php.ini; the packages alone do not load them.
RUN sed -i -E 's/^;(extension=(gd|intl|pdo_sqlite|sqlite3))$/\1/' /etc/php/php.ini

# Distro chromium instead of Playwright's own download (saves ~300 MB, stays
# pacman-patched). --no-sandbox is required as a non-root user in a container;
# the container is the isolation boundary. PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH is
# NOT a variable Playwright reads (the executable is chosen per launch, via the
# MCP server's command line); these vars are hints for scripts only.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/lib/chromium \
    CHROMIUM_PATH=/usr/bin/chromium

# ===========================================================================
# 7. Trail-Code (code map + learnings for coding agents), pinned
# The flag checks make a release that dropped what trail-ensure relies on fail
# the BUILD rather than the first session.
# ===========================================================================
RUN npm install -g "@trailhq/trail-code@${TRAIL_VERSION}" && \
    trail --version && \
    trail init --help 2>&1 | grep -q -- '--agents' && \
    trail init --help 2>&1 | grep -q -- '--yes' && \
    trail build --help 2>&1 | grep -q -- '--follow-submodules' && \
    trail build --help 2>&1 | grep -q -- '--follow-nested-repos'

# ===========================================================================
# 8. Scripts, assets, doctor checks, udev rules, Claude config
# ===========================================================================
COPY scripts/entrypoint.sh  /usr/local/bin/entrypoint.sh
COPY scripts/post-create.sh /usr/local/bin/post-create.sh
COPY scripts/dev-doctor.sh  /usr/local/bin/dev-doctor
COPY scripts/web-post-create.sh /usr/local/bin/web-post-create.sh
COPY scripts/dev-attach.sh  /usr/local/bin/dev-attach
COPY scripts/trail-ensure.sh /usr/local/bin/trail-ensure
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/post-create.sh \
             /usr/local/bin/dev-doctor /usr/local/bin/web-post-create.sh \
             /usr/local/bin/dev-attach /usr/local/bin/trail-ensure

# Embedded: profile task runner (`mcu`), per-target profiles, schema, shared CMake
# helpers and toolchain files, VSCode starters, svd-find. udev does NOT run inside
# a container, so udev-rules/ is shipped for install-host-udev-rules.sh to install
# on the HOST (kept under /opt/embedded so nobody mistakes them for active rules).
COPY embedded/run-profile-task.sh   /opt/embedded/run-profile-task.sh
COPY embedded/scripts/svd-find.sh   /opt/embedded/svd-find
COPY embedded/profile.schema.json   /opt/embedded/profile.schema.json
COPY embedded/profiles/             /opt/embedded/profiles/
COPY embedded/cmake/                /opt/embedded/cmake/
COPY embedded/vscode-templates/     /opt/embedded/vscode-templates/
COPY embedded/udev-rules/           /opt/embedded/udev-rules/
COPY scripts/install-host-udev-rules.sh /opt/embedded/install-host-udev-rules.sh
COPY embedded/scripts/ch58x-sdk.sh  /usr/local/bin/ch58x-sdk
RUN chmod +x /opt/embedded/run-profile-task.sh /opt/embedded/svd-find \
             /opt/embedded/install-host-udev-rules.sh /usr/local/bin/ch58x-sdk && \
    ln -sf /opt/embedded/run-profile-task.sh /usr/local/bin/mcu && \
    ln -sf /opt/embedded/svd-find            /usr/local/bin/svd-find

# Web: profile task runner (`web build`, `web test`, ...), schema, VSCode starters.
COPY web/run-web-task.sh         /opt/web/run-web-task.sh
COPY web/web-profile.schema.json /opt/web/web-profile.schema.json
COPY web/vscode-templates/       /opt/web/vscode-templates/
RUN chmod +x /opt/web/run-web-task.sh && \
    ln -sf /opt/web/run-web-task.sh /usr/local/bin/web

# dev-doctor checks contributed by every platform (drop-in directory)
RUN mkdir -p /opt/dev-doctor/checks.d
COPY dev-doctor-checks/ /opt/dev-doctor/checks.d/
RUN chmod +x /opt/dev-doctor/checks.d/*.sh

# Per-user tooling and Claude config, as the non-root user
USER ${USER_NAME}
WORKDIR /home/${USER_NAME}

# Claude Code via the official installer (lands in ~/.local/bin, supports `claude update`)
RUN curl -fsSL https://claude.ai/install.sh | bash

# bun: fast JS runtime and package manager
RUN curl -fsSL https://bun.sh/install | bash

# Telink: the SDK's tc32 binary lives behind a host mount; it is on PATH here and
# simply does not resolve when nothing is mounted (expected, not a broken image).
ENV PATH="/home/${USER_NAME}/.bun/bin:/home/${USER_NAME}/.local/bin:/opt/telink/sdk/tools/tc32/bin:${PATH}"

# Trail's anonymous usage ping is off by default (re-enable: `trail telemetry enable`).
# Deliberately NOT a global DO_NOT_TRACK, which would silence unrelated tools too.
RUN trail telemetry disable

# Superpowers plugin, user scope, baked in so there is no network round-trip at
# container start. It lives under ~/.claude/plugins, which is not a bind-mounted
# path. The *enabled* flag is declared in claude-baseline/settings.json because
# entrypoint.sh regenerates settings.json from ~/.claude-layers on every start.
RUN claude plugin marketplace add anthropics/claude-plugins-official && \
    claude plugin install superpowers@claude-plugins-official --scope user && \
    claude plugin list | grep -q 'superpowers@claude-plugins-official'

# Baked-in Claude config: skills/, agents/, commands/ stay image-owned; auth,
# projects and memory are shared via bind mounts at runtime.
COPY --chown=${USER_UID}:${USER_GID} claude-baseline/skills/   /home/${USER_NAME}/.claude/skills/
COPY --chown=${USER_UID}:${USER_GID} claude-baseline/agents/   /home/${USER_NAME}/.claude/agents/
COPY --chown=${USER_UID}:${USER_GID} claude-baseline/commands/ /home/${USER_NAME}/.claude/commands/

# settings.json is NOT copied directly: entrypoint.sh merges ~/.claude-layers/*.json
# (lexical order) into ~/.claude/settings.json at every start, and concatenates
# ~/.claude-memory-layers/*.md into ~/.claude/CLAUDE.md. The image ships one layer
# each; a user can add a private numbered layer without touching these.
COPY --chown=${USER_UID}:${USER_GID} claude-baseline/settings.json \
     /home/${USER_NAME}/.claude-layers/00-baseline.json
COPY --chown=${USER_UID}:${USER_GID} claude-baseline/CLAUDE.layer.md \
     /home/${USER_NAME}/.claude-memory-layers/00-baseline.md

# Default user stays ${USER_NAME}; the entrypoint's root phase is inert here.
# To use the UID/GID remap, start the container as root and let the entrypoint
# drop privileges itself (dev-up.sh does this when the host UID is not 1000):
#     docker run --user 0:0 -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) ...
USER ${USER_NAME}
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]

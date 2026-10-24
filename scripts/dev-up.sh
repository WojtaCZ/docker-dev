#!/usr/bin/env bash
# Headless build + run for the unified dev container on Linux.
#
# One image holds every toolchain (ARM Cortex-M, WCH RISC-V, Telink runtime, web),
# the debug probes' userland and Trail-Code. Devices are passed through LIVE: probes,
# boards, serial ports, HID, input and ALSA nodes can be attached after start.
#
# Usage:
#   ./scripts/dev-up.sh                   # workspace = $(pwd)
#   ./scripts/dev-up.sh /path/to/project
#
# The project is mounted at /workspaces/<name>-<hash> (the hash keeps two folders
# with the same name apart, so Claude's per-project memory never mixes them); the
# container's /workspace is a symlink to it, set up by entrypoint.sh.
#
# Env vars:
#   DEV_IMAGE=<name>       image tag              (default: dev-template)
#   DEV_CONTAINER=<name>   running container name (default: dev)
#   DEV_NO_BUILD=1         skip docker build
#   DEV_NO_PULL=1          don't --pull the base image (offline / pin)
#   DEV_REBUILD=1          docker build --no-cache
#   DEV_NO_CACHE_VOLUMES=1 don't mount the persistent package caches
#   DEV_SKIP_UPDATE=1      skip `claude update` on container start
#   DEV_DOCTOR=1           run dev-doctor and exit
#   DEV_TRAIL=0            do not auto-set-up Trail-Code in projects (also: a `.no-trail` file)
#   DEV_PROBE=/dev/ttyXX   additional single device to pass through (static: must
#                          exist at container start, unlike /dev/bus/usb below)
#   DEV_PORTS="3000 8080"  extra ports to publish on 127.0.0.1
#   DEV_NO_SERVICES=1      don't join the docker-compose service network
#   DEV_ASSETS=<path>      read-only mount at /opt/assets for licence-encumbered
#                          material (commercial fonts, private registry creds, ...)
#   DEV_STATE_DIR=<path>   container-private Claude state (default ~/.claude-dev):
#                          prompt history, file-history, backups, sessions, ...
#                          kept apart from the host's ~/.claude so pids and
#                          sessions of the two never collide
#   DEV_PRINT=1            print the final `docker run` argv, one per line, and exit
#                          (no build, no docker call; used by the unit tests)
#
# Optional host-mounted vendor tooling (none is redistributable, so none is baked
# into the image). Each is auto-detected at its default path:
#   DEV_TELINK_SDK=<path>  Telink SDK     -> /opt/telink/sdk   (default ~/telink/Telink_825X_SDK)
#                          carries the tc32 compiler blob under tools/tc32/bin
#   DEV_CUBECLT=<path>     STM32CubeCLT   -> /opt/st/clt       (default ~/st/STM32CubeCLT)
#                          STM32_Programmer_CLI + ST-LINK GDB server; day-one silicon support
#   DEV_CUBEWBA=<path>     STM32CubeWBA   -> /opt/st/cubewba   (default ~/st/cubewba)
#                          REQUIRED for BLE on STM32WBA (ST binary libraries, SLA0044)
#
# Test hooks (default to the real system): DEV_ROOT=/dev, DEV_PROC_DEVICES=/proc/devices,
# DEV_DBUS_SOCKET=/run/dbus/system_bus_socket.

set -euo pipefail

IMAGE_NAME="${DEV_IMAGE:-dev-template}"
CONTAINER_NAME="${DEV_CONTAINER:-dev}"
WORKSPACE_ARG="${1:-$(pwd)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEV_ROOT="${DEV_ROOT:-/dev}"
PROC_DEVICES="${DEV_PROC_DEVICES:-/proc/devices}"
BT_SOCK="${DEV_DBUS_SOCKET:-/run/dbus/system_bus_socket}"
PRINT="${DEV_PRINT:-0}"

# Host-side files and directories that must exist before they can be bind-mounted.
# In DEV_PRINT mode nothing on the host is created.
ensure_dir()  { [ "$PRINT" = "1" ] || mkdir -p "$1"; }
ensure_file() { [ "$PRINT" = "1" ] || { mkdir -p "$(dirname "$1")"; touch "$1"; }; }

# Major number of a /proc/devices entry, read rather than hardcoded: hidraw's is
# assigned dynamically at module load (it differs between boots).
major_of() { awk -v n="$1" '$2 == n { print $1 }' "$PROC_DEVICES" 2>/dev/null || true; }

# Mount name for a workspace: <sanitised basename>-<first 8 hex of sha256(abs path)>.
workspace_mount_name() {
    local abs="$1" base
    base="$(printf '%s' "$(basename "$abs")" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
    [ -n "$base" ] && [ "$base" != "/" ] || base="root"
    printf '%s-%s' "$base" "$(printf '%s' "$abs" | sha256sum | cut -c1-8)"
}

WORKSPACE="$(cd "$WORKSPACE_ARG" && pwd -P)"
WS_MOUNT="/workspaces/$(workspace_mount_name "$WORKSPACE")"

if [ "$PRINT" != "1" ] && [ "${DEV_NO_BUILD:-0}" != "1" ]; then
    BUILD_FLAGS=()
    [ "${DEV_NO_PULL:-0}" != "1" ] && BUILD_FLAGS+=("--pull")
    [ "${DEV_REBUILD:-0}" = "1" ]  && BUILD_FLAGS+=("--no-cache")
    docker build "${BUILD_FLAGS[@]}" -t "$IMAGE_NAME" "$REPO_ROOT"
fi

CLAUDE_JSON="$HOME/.claude.json"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_CREDS="$CLAUDE_DIR/.credentials.json"
STATE_DIR="${DEV_STATE_DIR:-$HOME/.claude-dev}"
if [ ! -f "$CLAUDE_JSON" ]; then
    echo "WARN: $CLAUDE_JSON not found. Run 'claude' on the host at least once." >&2
fi
ensure_dir "$CLAUDE_DIR"
ensure_file "$CLAUDE_JSON"
if [ "$PRINT" != "1" ]; then
    [ -f "$CLAUDE_CREDS" ] || { touch "$CLAUDE_CREDS"; chmod 600 "$CLAUDE_CREDS"; }
fi

# .claude.json and .credentials.json are bind-mounted straight onto their final
# in-container paths, NOT through an entrypoint-time symlink. `claude login`
# persists credentials with a write-temp-then-rename(2), and rename(2) onto a plain
# symlink just replaces the symlink with a new inode, silently orphaning the host
# file, so a login done inside a --rm container never survived a restart. A real
# bind mount IS a mount point: rename(2) onto it fails EBUSY, which Claude Code's
# credential writer catches and falls back to copyFile(), which writes through to
# the real host file.
MOUNTS=(
    -v "$WORKSPACE:$WS_MOUNT"
    -v "$CLAUDE_JSON:/home/dev/.claude.json"
    -v "$CLAUDE_CREDS:/home/dev/.claude/.credentials.json"
)
# Transcripts and per-project memory are shared with the host's Claude on purpose.
for shared in projects memory; do
    if [ -e "$CLAUDE_DIR/$shared" ]; then
        MOUNTS+=(-v "$CLAUDE_DIR/$shared:/home/dev/.claude/$shared")
    fi
done

# Everything else the container's Claude keeps that would die with a --rm container
# (prompt history, undo snapshots, backups, session registry) lives in a
# container-private host directory, so a re-run picks up where the last one left off.
STATE_FILES=(history.jsonl)
STATE_DIRS=(file-history backups sessions session-env shell-snapshots)
for f in "${STATE_FILES[@]}"; do
    ensure_file "$STATE_DIR/$f"
    MOUNTS+=(-v "$STATE_DIR/$f:/home/dev/.claude/$f")
done
for d in "${STATE_DIRS[@]}"; do
    ensure_dir "$STATE_DIR/$d"
    MOUNTS+=(-v "$STATE_DIR/$d:/home/dev/.claude/$d")
done

# Trail-Code personal learnings: shared with the host so they follow the user.
ensure_dir "$HOME/.trail"
MOUNTS+=(-v "$HOME/.trail:/home/dev/.trail")

# Persistent package caches. Without these every `--rm` run re-downloads npm, uv,
# cargo, composer, bun and deno content from scratch.
if [ "${DEV_NO_CACHE_VOLUMES:-0}" != "1" ]; then
    MOUNTS+=(
        -v "dev-cache-npm:/home/dev/.npm"
        -v "dev-cache-uv:/home/dev/.cache/uv"
        -v "dev-cache-cargo:/home/dev/.cargo"
        -v "dev-cache-pkg:/home/dev/.cache/pkg"
        -v "dev-cache-pyocd:/opt/pyocd"
        -v "dev-cache-ccache:/home/dev/.cache/ccache"
        -v "dev-cache-bun:/home/dev/.bun/install/cache"
        -v "dev-cache-deno:/home/dev/.cache/deno"
        -v "dev-cache-composer:/home/dev/.cache/composer"
    )
fi

# Optional vendor tooling, mounted read-only if present on the host.
TELINK_SDK="${DEV_TELINK_SDK:-$HOME/telink/Telink_825X_SDK}"
CUBECLT="${DEV_CUBECLT:-$HOME/st/STM32CubeCLT}"
CUBEWBA="${DEV_CUBEWBA:-$HOME/st/cubewba}"
if [ -d "$TELINK_SDK" ]; then
    MOUNTS+=(-v "$TELINK_SDK:/opt/telink/sdk:ro")
    echo "info: mounting Telink SDK from $TELINK_SDK" >&2
fi
if [ -d "$CUBECLT" ]; then
    MOUNTS+=(-v "$CUBECLT:/opt/st/clt:ro")
    echo "info: mounting STM32CubeCLT from $CUBECLT" >&2
fi
if [ -d "$CUBEWBA" ]; then
    MOUNTS+=(-v "$CUBEWBA:/opt/st/cubewba:ro")
    echo "info: mounting STM32CubeWBA from $CUBEWBA (BLE stack available)" >&2
fi
if [ -n "${DEV_ASSETS:-}" ] && [ -d "$DEV_ASSETS" ]; then
    MOUNTS+=(-v "$DEV_ASSETS:/opt/assets:ro")
    echo "info: mounting assets from $DEV_ASSETS at /opt/assets" >&2
fi

# USB / probe passthrough: hotplug-capable, no container restart needed to pick up
# a probe attached after this script has started the container.
#
# `--device=/dev/bus/usb` makes Docker walk the directory ONCE at creation, mknod
# only the nodes it finds then, and cgroup-allow only those major:minor pairs;
# anything plugged in afterwards is invisible because the device cgroup never
# allowed it. Fix: bind-mount the directory itself (a live view) and grant a
# wildcard on USB's kernel-assigned major (189) with --device-cgroup-rule, so every
# future minor is already permitted. This also means probes the container has never
# seen work with no vendor/product allow-list.
USB_ARGS=()
if [ -d "$DEV_ROOT/bus/usb" ]; then
    USB_ARGS+=(-v "$DEV_ROOT/bus/usb:/dev/bus/usb" --device-cgroup-rule='c 189:* rmw')
else
    echo "WARN: $DEV_ROOT/bus/usb not present on this host; no probe passthrough." >&2
fi
[ -d "$DEV_ROOT/serial/by-id" ] && USB_ARGS+=(-v "$DEV_ROOT/serial/by-id:/dev/serial/by-id:ro")
# /sys/bus/usb is deliberately NOT bind-mounted: Docker Desktop's WSL integration
# replays every bind source when its distro proxy starts and fails the whole
# integration if one no longer exists. The container's own /sys has it anyway.
# DEV_PROBE stays a static, one-shot --device.
[ -n "${DEV_PROBE:-}" ] && [ -e "$DEV_PROBE" ] && USB_ARGS+=(--device="$DEV_PROBE")

# Flat /dev nodes (hidraw, ttyACM, ttyUSB) have no per-subsystem directory to
# bind-mount live and a bind-mounted node is pinned to one host inode, so they are
# NOT bind-mounted: scripts/dev-attach.sh mknods them into the running container,
# once at start (watcher below) and on every hotplug via its udev rule. The cgroup
# grant is still a wildcard on each major (read from /proc/devices), so a node that
# appears later only needs a mknod, never a new container.
#   hidraw : a USB device under test that enumerates as HID
#   ttyACM : CDC-ACM debug probes' virtual COM port (ST-Link VCP, ...)
#   ttyUSB : USB-serial adapters (FTDI/CP210x/CH340, the Telink programmer path)
for subsys in hidraw ttyACM ttyUSB; do
    major="$(major_of "$subsys")"
    [ -n "$major" ] && USB_ARGS+=(--device-cgroup-rule="c $major:* rmw")
done

# /dev/input (touch panels, styluses, anything with a Linux input handler) and
# /dev/snd (USB-MIDI interfaces) ARE per-subsystem directories: bind mounts are live.
INPUT_MAJOR="$(major_of input)"
if [ -d "$DEV_ROOT/input" ]; then
    USB_ARGS+=(-v "$DEV_ROOT/input:/dev/input")
    [ -n "$INPUT_MAJOR" ] && USB_ARGS+=(--device-cgroup-rule="c $INPUT_MAJOR:* rmw")
else
    echo "WARN: $DEV_ROOT/input not present on this host; no touch/HID input passthrough." >&2
fi
ALSA_MAJOR="$(major_of alsa)"
if [ -d "$DEV_ROOT/snd" ] && [ -n "$ALSA_MAJOR" ]; then
    USB_ARGS+=(-v "$DEV_ROOT/snd:/dev/snd" --device-cgroup-rule="c $ALSA_MAJOR:* rmw")
else
    echo "WARN: $DEV_ROOT/snd not present on this host; no ALSA MIDI passthrough." >&2
fi

# Bluetooth: the host's bluetoothd owns the adapter; the container only needs the
# system D-Bus socket to reach it (bluetoothctl, bleak, BlueZ D-Bus API). No
# --net=host or raw HCI access. A single-file live bind mount, so it must exist at
# container start.
if [ -S "$BT_SOCK" ] || { [ "$PRINT" = "1" ] && [ -e "$BT_SOCK" ]; }; then
    USB_ARGS+=(-v "$BT_SOCK:$BT_SOCK")
else
    echo "WARN: $BT_SOCK not present on this host; no Bluetooth passthrough." >&2
fi

# The numeric dialout/plugdev/input GIDs differ between the Arch container and the
# host distro, so pass the host's through explicitly. A device-cgroup-rule only
# grants the cgroup permission to open the node; the node itself is root:<group>
# 0660, so `dev` must be in that GID to read() it. Arch-family hosts have no
# dialout (serial nodes are root:uucp, ALSA nodes root:audio).
GROUP_ARGS=()
for g in dialout plugdev input uucp audio; do
    gid="$(getent group "$g" 2>/dev/null | cut -d: -f3 || true)"
    [ -n "$gid" ] && GROUP_ARGS+=(--group-add "$gid")
done

# UID alignment for the bind-mounted workspace.
USER_ARGS=()
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
if [ "$HOST_UID" != "1000" ] || [ "$HOST_GID" != "1000" ]; then
    USER_ARGS=(--user 0:0 -e "HOST_UID=$HOST_UID" -e "HOST_GID=$HOST_GID")
fi

ENV_ARGS=(-e "DEV_WORKSPACE=$WS_MOUNT")
[ "${DEV_SKIP_UPDATE:-0}" = "1" ] && ENV_ARGS+=(-e DEV_SKIP_UPDATE=1)
[ "${DEV_TRAIL:-1}" = "0" ] && ENV_ARGS+=(-e DEV_TRAIL=0)
[ -n "${GITHUB_TOKEN:-}" ] && ENV_ARGS+=(-e "GITHUB_TOKEN=$GITHUB_TOKEN")

# Git identity: reuse the host's, passed as env rather than copying ~/.gitconfig
# (which would drag host-specific credential helpers and paths into the container).
GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"
if [ -n "$GIT_NAME" ]; then
    ENV_ARGS+=(-e "GIT_AUTHOR_NAME=$GIT_NAME" -e "GIT_COMMITTER_NAME=$GIT_NAME")
fi
if [ -n "$GIT_EMAIL" ]; then
    ENV_ARGS+=(-e "GIT_AUTHOR_EMAIL=$GIT_EMAIL" -e "GIT_COMMITTER_EMAIL=$GIT_EMAIL")
fi

SSH_ARGS=()
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    SSH_ARGS=(-v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent)
elif [ "$(uname -s)" = "Darwin" ]; then
    # Docker Desktop for Mac exposes the host ssh-agent at this magic socket
    SSH_ARGS=(-v /run/host-services/ssh-auth.sock:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent)
else
    echo "WARN: SSH_AUTH_SOCK not set; git over SSH won't work inside the container." >&2
fi

# Publish dev-server ports on loopback only (the web interface of whatever you build).
PORT_ARGS=()
for p in ${DEV_PORTS:-}; do
    PORT_ARGS+=(-p "127.0.0.1:${p}:${p}")
done

# Join the backing-services network if `docker compose -f compose/docker-compose.yml up -d`
# has been run (mariadb, postgres, redis, mailpit).
NET_ARGS=()
if [ "${DEV_NO_SERVICES:-0}" != "1" ] && [ "$PRINT" != "1" ] && \
   docker network inspect docker-dev-web >/dev/null 2>&1; then
    NET_ARGS=(--network docker-dev-web)
    echo "info: joining the docker-dev-web service network (mariadb, postgres, redis, mailpit)" >&2
fi

CMD_ARGS=()
[ "${DEV_DOCTOR:-0}" = "1" ] && CMD_ARGS=(dev-doctor)

DOCKER_ARGV=(
    run --rm -it
    --name "$CONTAINER_NAME"
    --init
    -w "$WS_MOUNT"
    "${MOUNTS[@]}"
    "${USB_ARGS[@]}"
    "${GROUP_ARGS[@]}"
    "${USER_ARGS[@]}"
    "${ENV_ARGS[@]}"
    "${SSH_ARGS[@]}"
    "${PORT_ARGS[@]}"
    "${NET_ARGS[@]}"
    "$IMAGE_NAME" "${CMD_ARGS[@]}"
)

if [ "$PRINT" = "1" ]; then
    printf '%s\n' "${DOCKER_ARGV[@]}"
    exit 0
fi

# Mirror the flat nodes that already exist into the container once it is up.
# `exec docker run` below replaces this shell, so this runs as a background watcher
# that polls for the container and then hands off to dev-attach.sh.
(
    nodes=()
    for node in "$DEV_ROOT"/ttyACM* "$DEV_ROOT"/ttyUSB* "$DEV_ROOT"/hidraw*; do
        [ -c "$node" ] && nodes+=("$node")
    done
    [ "${#nodes[@]}" -gt 0 ] || exit 0
    for _ in $(seq 1 100); do
        if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]; then
            DEV_CONTAINER="$CONTAINER_NAME" "$(dirname "${BASH_SOURCE[0]}")/dev-attach.sh" attach "${nodes[@]}" >&2
            exit 0
        fi
        sleep 0.2
    done
    echo "WARN: container '$CONTAINER_NAME' did not come up in 20s; flat nodes not attached." >&2
) &

exec docker "${DOCKER_ARGV[@]}"

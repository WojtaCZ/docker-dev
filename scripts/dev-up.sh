#!/usr/bin/env bash
# Headless build + run for the baseline dev container on Linux/macOS.
#
# Usage:
#   ./scripts/dev-up.sh                 # workspace = $(pwd)
#   ./scripts/dev-up.sh /path/to/proj   # workspace = /path/to/proj
#
# Env vars:
#   DEV_IMAGE=<name>      image tag              (default: dev-template-baseline)
#   DEV_CONTAINER=<name>  running container name (default: dev-template)
#   DEV_NO_BUILD=1        skip docker build
#   DEV_NO_PULL=1         don't `--pull` the base image (offline / pin)
#   DEV_REBUILD=1         docker build --no-cache
#   DEV_NO_CACHE_VOLUMES=1  don't mount the persistent package-cache volumes
#   DEV_SKIP_UPDATE=1     skip `claude update` on container start
#   DEV_DOCTOR=1          run dev-doctor instead of an interactive shell

set -euo pipefail

IMAGE_NAME="${DEV_IMAGE:-dev-template-baseline}"
CONTAINER_NAME="${DEV_CONTAINER:-dev-template}"
WORKSPACE="${1:-$(pwd)}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${DEV_NO_BUILD:-0}" != "1" ]; then
    BUILD_FLAGS=()
    [ "${DEV_NO_PULL:-0}" != "1" ] && BUILD_FLAGS+=("--pull")
    [ "${DEV_REBUILD:-0}" = "1" ]  && BUILD_FLAGS+=("--no-cache")
    docker build "${BUILD_FLAGS[@]}" -t "$IMAGE_NAME" "$REPO_ROOT"
fi

CLAUDE_JSON="$HOME/.claude.json"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_CREDS="$CLAUDE_DIR/.credentials.json"

if [ ! -f "$CLAUDE_JSON" ]; then
    echo "WARN: $CLAUDE_JSON not found. Run 'claude' on the host at least once." >&2
fi
mkdir -p "$CLAUDE_DIR"
touch "$CLAUDE_JSON"
[ -f "$CLAUDE_CREDS" ] || { touch "$CLAUDE_CREDS"; chmod 600 "$CLAUDE_CREDS"; }

# .claude.json and .credentials.json are bind-mounted straight onto their
# final in-container paths, NOT through entrypoint.sh's symlink-after-copy at
# /host-claude-auth.json / /host-claude-dir (which now harmlessly no-ops,
# since those paths are never populated here anymore — see the removed block
# below). `claude login` persists credentials with a write-temp-then-
# rename(2), and rename(2) onto a plain symlink just replaces the symlink
# with a new inode — silently orphaning the host file — so a login done only
# inside a --rm container never survived a restart. A real bind mount IS a
# mount point: rename(2) onto it fails EBUSY, which Claude Code's credential
# writer specifically catches and falls back to copyFile(), which writes
# through to the real host file. Verified against the shipped `claude`
# binary's write path and reproduced end-to-end with both mount styles.
MOUNTS=(
    -v "$WORKSPACE:/workspace"
    -v "$CLAUDE_JSON:/home/dev/.claude.json"
    -v "$CLAUDE_CREDS:/home/dev/.claude/.credentials.json"
)
for shared in projects memory; do
    if [ -e "$CLAUDE_DIR/$shared" ]; then
        MOUNTS+=(-v "$CLAUDE_DIR/$shared:/home/dev/.claude/$shared")
    fi
done

# Persistent package caches. Without these every `--rm` run re-downloads npm,
# uv and cargo content from scratch — the single biggest startup cost.
if [ "${DEV_NO_CACHE_VOLUMES:-0}" != "1" ]; then
    MOUNTS+=(
        -v "dev-cache-npm:/home/dev/.npm"
        -v "dev-cache-uv:/home/dev/.cache/uv"
        -v "dev-cache-cargo:/home/dev/.cargo"
        -v "dev-cache-pkg:/home/dev/.cache/pkg"
    )
fi

# UID/GID alignment. Files written into the bind-mounted workspace must be
# owned by the host user. When the host UID is not the baked-in 1000 we start
# the container as root and let entrypoint.sh remap and drop privileges.
USER_ARGS=()
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
if [ "$HOST_UID" != "1000" ] || [ "$HOST_GID" != "1000" ]; then
    USER_ARGS=(--user 0:0 -e "HOST_UID=$HOST_UID" -e "HOST_GID=$HOST_GID")
fi

ENV_ARGS=()
[ "${DEV_SKIP_UPDATE:-0}" = "1" ] && ENV_ARGS+=(-e DEV_SKIP_UPDATE=1)
[ -n "${GITHUB_TOKEN:-}" ] && ENV_ARGS+=(-e "GITHUB_TOKEN=$GITHUB_TOKEN")

SSH_ARGS=()
case "$(uname -s)" in
    Darwin)
        # Docker Desktop for Mac exposes host ssh-agent at this magic socket
        SSH_ARGS=(-v /run/host-services/ssh-auth.sock:/ssh-agent
                  -e SSH_AUTH_SOCK=/ssh-agent)
        ;;
    Linux)
        if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
            SSH_ARGS=(-v "$SSH_AUTH_SOCK:/ssh-agent"
                      -e SSH_AUTH_SOCK=/ssh-agent)
        else
            echo "WARN: SSH_AUTH_SOCK not set; git over SSH won't work inside the container." >&2
        fi
        ;;
esac

CMD_ARGS=()
[ "${DEV_DOCTOR:-0}" = "1" ] && CMD_ARGS=(dev-doctor)

exec docker run --rm -it \
    --name "$CONTAINER_NAME" \
    --init \
    "${MOUNTS[@]}" \
    "${USER_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    "${SSH_ARGS[@]}" \
    "$IMAGE_NAME" "${CMD_ARGS[@]}"

#!/usr/bin/env bash
# Add or remove flat /dev nodes (ttyACM*, ttyUSB*, hidraw*) in the RUNNING dev container.
#
# Usage:
#   ./scripts/dev-attach.sh attach /dev/ttyACM3 [/dev/hidraw2 ...]
#   ./scripts/dev-attach.sh detach /dev/ttyACM3
#
# Env vars:
#   DEV_CONTAINER=<name>   running container name (default: dev)
#
# Why this exists: /dev/bus/usb, /dev/input and /dev/snd are bind-mounted as live
# directories by dev-up.sh, so nodes under them appear on their own. ttyACM,
# ttyUSB and hidraw nodes are flat in /dev and can't be mounted that way. dev-up.sh does
# grant the container's device cgroup a wildcard on their major numbers, so the
# only thing missing for a node that appears later is the node itself — which is
# a mknod away. This does that mknod as root inside the container, copying the
# host node's major:minor, mode and group.
#
# Also driven by udev (udev-rules/90-dev-emb-attach.rules.in, installed by
# install-host-udev-rules.sh) so plugging a device in is all it takes. In that
# mode the container may legitimately not be running; that is not an error.
#
# Limitation: a node that dev-up.sh bind-mounted at start cannot be replaced
# (EBUSY). It keeps working as long as the re-plugged device gets the same
# minor, which is the usual case.

set -uo pipefail

CONTAINER="${DEV_CONTAINER:-dev}"
ACTION="${1:-}"
shift || true

if [ -z "$ACTION" ] || [ $# -eq 0 ]; then
    sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
fi

# Quietly do nothing when there is no container to attach to.
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
    echo "info: container '$CONTAINER' is not running — nothing to $ACTION." >&2
    exit 0
fi

rc=0
for node in "$@"; do
    case "$node" in
        /dev/ttyACM[0-9]* | /dev/ttyUSB[0-9]* | /dev/hidraw[0-9]*) ;;
        *)
            echo "skip: $node (only flat ttyACM/ttyUSB/hidraw nodes; /dev/bus/usb, /dev/input and /dev/snd are already live)" >&2
            continue
            ;;
    esac

    case "$ACTION" in
        attach)
            if [ ! -c "$node" ]; then
                echo "error: $node is not a character device on the host" >&2
                rc=1
                continue
            fi
            # stat prints major/minor in hex; mknod wants decimal.
            read -r maj min mode gid < <(stat -c '%t %T %a %g' "$node")
            maj=$((16#$maj)); min=$((16#$min))
            if docker exec -u root "$CONTAINER" sh -c \
                'rm -f "$1" && mknod -m "$2" "$1" c "$3" "$4" && chgrp "$5" "$1"' \
                _ "$node" "$mode" "$maj" "$min" "$gid"; then
                echo "attached $node ($maj:$min, mode $mode, gid $gid) -> $CONTAINER"
            else
                echo "error: could not create $node in $CONTAINER (bind-mounted at start, or major $maj not granted — re-run dev-up.sh)" >&2
                rc=1
            fi
            ;;
        detach)
            # The host node is already gone on unplug, so use the path only.
            if docker exec -u root "$CONTAINER" rm -f "$node" 2>/dev/null; then
                echo "detached $node <- $CONTAINER"
            else
                echo "warn: could not remove $node from $CONTAINER (still bind-mounted?)" >&2
            fi
            ;;
        *)
            echo "error: unknown action '$ACTION' (attach|detach)" >&2
            exit 2
            ;;
    esac
done
exit "$rc"

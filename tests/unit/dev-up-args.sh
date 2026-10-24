#!/usr/bin/env bash
# dev-up.sh argument construction, checked through DEV_PRINT=1 (prints the docker
# run argv one per line and exits before touching docker).
# Run: bash tests/run-unit.sh tests/unit/dev-up-args.sh
set -uo pipefail

UP="${UP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/dev-up.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok  $1"; else echo "FAIL: $1: expected [$2] got [$3]" >&2; fails=$((fails + 1)); fi; }
has() { grep -Fxq -- "$2" <<< "$OUT"; }       # has <name> <exact argv line>
expect() { if has "$1" "$2"; then echo "  ok  $1"; else echo "FAIL: $1: argv lacks [$2]" >&2; fails=$((fails + 1)); fi; }
lacks() { if has "$1" "$2"; then echo "FAIL: $1: argv unexpectedly has [$2]" >&2; fails=$((fails + 1)); else echo "  ok  $1"; fi; }

# --- a fully populated fake host ------------------------------------------------
H="$T/home"; DEVROOT="$T/dev"
mkdir -p "$H/.claude/projects" "$DEVROOT/bus/usb" "$DEVROOT/input" "$DEVROOT/snd" "$DEVROOT/serial/by-id" \
         "$H/telink/Telink_825X_SDK" "$H/st/STM32CubeCLT" "$H/st/cubewba" "$T/ws/app"
touch "$H/.claude.json" "$H/.claude/.credentials.json" "$T/dbus.sock"
cat > "$T/devices" <<'DEVS'
Character devices:
  13 input
 116 alsa
 166 ttyACM
 188 ttyUSB
 189 usb
 243 hidraw
DEVS
base_env=(HOME="$H" DEV_PRINT=1 DEV_NO_BUILD=1 DEV_ROOT="$DEVROOT" DEV_PROC_DEVICES="$T/devices"
          DEV_DBUS_SOCKET="$T/dbus.sock" SSH_AUTH_SOCK=)
runup() { OUT="$(env "${base_env[@]}" "$@" 2>"$T/err")"; RC=$?; }

runup "$UP" "$T/ws/app"
check "exit 0" 0 "$RC"
expect "usb cgroup rule" "--device-cgroup-rule=c 189:* rmw"
expect "hidraw cgroup rule" "--device-cgroup-rule=c 243:* rmw"
expect "ttyACM cgroup rule" "--device-cgroup-rule=c 166:* rmw"
expect "ttyUSB cgroup rule" "--device-cgroup-rule=c 188:* rmw"
expect "input cgroup rule" "--device-cgroup-rule=c 13:* rmw"
expect "alsa cgroup rule" "--device-cgroup-rule=c 116:* rmw"
expect "usb live bind mount" "$DEVROOT/bus/usb:/dev/bus/usb"
expect "dbus socket mounted" "$T/dbus.sock:$T/dbus.sock"

ws_abs="$(cd "$T/ws/app" && pwd -P)"
hash8="$(printf '%s' "$ws_abs" | sha256sum | cut -c1-8)"
mount_name="app-$hash8"
expect "workspace mounted at /workspaces/<name>-<hash>" "$ws_abs:/workspaces/$mount_name"
expect "workdir is the project mount" "/workspaces/$mount_name"
expect "DEV_WORKSPACE passed" "DEV_WORKSPACE=/workspaces/$mount_name"

expect ".claude.json final path" "$H/.claude.json:/home/dev/.claude.json"
expect "credentials final path" "$H/.claude/.credentials.json:/home/dev/.claude/.credentials.json"
expect "projects shared" "$H/.claude/projects:/home/dev/.claude/projects"
for s in history.jsonl file-history backups sessions session-env shell-snapshots; do
    expect "persisted state: $s" "$H/.claude-dev/$s:/home/dev/.claude/$s"
done
expect ".trail persisted" "$H/.trail:/home/dev/.trail"
expect "telink SDK mount" "$H/telink/Telink_825X_SDK:/opt/telink/sdk:ro"
expect "CubeCLT mount" "$H/st/STM32CubeCLT:/opt/st/clt:ro"
expect "CubeWBA mount" "$H/st/cubewba:/opt/st/cubewba:ro"
expect "pyocd cache volume" "dev-cache-pyocd:/opt/pyocd"
expect "composer cache volume" "dev-cache-composer:/home/dev/.cache/composer"
expect "image default" "dev-template"
expect "container default is per project (two projects can run side by side)" "dev-$mount_name"
expect "container labelled for dev-attach" "dev.attach=1"
runup DEV_CONTAINER=custom "$UP" "$T/ws/app"
expect "DEV_CONTAINER still overrides" "custom"
runup "$UP" "$T/ws/app"

# --- review focus 3: odd workspace paths ---------------------------------------
mkdir -p "$T/my proj" "$T/ünï" "$T/a/app" "$T/b/app"
names=()
for p in "$T/my proj/" "$T/ünï" "$T/a/app" "$T/b/app"; do
    runup "$UP" "$p"
    check "exit 0 for [$p]" 0 "$RC"
    n="$(grep -Eo '^.*:/workspaces/[^ ]+$' <<< "$OUT" | head -1 | sed 's|.*:/workspaces/||')"
    case "$n" in (*[!A-Za-z0-9._-]*|"") echo "FAIL: invalid mount name [$n] for [$p]" >&2; fails=$((fails + 1)) ;; (*) echo "  ok  valid name $n" ;; esac
    names+=("$n")
done
check "same basename, different dirs -> different names" "different" \
    "$([ "${names[2]}" != "${names[3]}" ] && echo different || echo same)"

# --- review focus 5: nothing optional exists -----------------------------------
EMPTY="$T/empty"; mkdir -p "$EMPTY/home" "$EMPTY/dev" "$EMPTY/ws"
: > "$EMPTY/devices"
OUT="$(env HOME="$EMPTY/home" DEV_PRINT=1 DEV_NO_BUILD=1 DEV_ROOT="$EMPTY/dev" DEV_PROC_DEVICES="$EMPTY/devices" \
        DEV_DBUS_SOCKET="$EMPTY/none.sock" SSH_AUTH_SOCK= "$UP" "$EMPTY/ws" 2>"$T/err2")"; RC=$?
check "bare host: exit 0" 0 "$RC"
check "bare host: still a docker run argv" "run" "$(grep -m1 -Fx run <<< "$OUT")"
lacks "bare host: no telink mount" "$EMPTY/home/telink/Telink_825X_SDK:/opt/telink/sdk:ro"
check "bare host: warnings go to stderr only" "" "$(grep -c '^WARN' <<< "$OUT" | grep -v '^0$')"

# --- switches carried over ------------------------------------------------------
runup DEV_TRAIL=0 DEV_PORTS="3000 8080" DEV_SKIP_UPDATE=1 "$UP" "$T/ws/app"
expect "DEV_TRAIL passed through" "DEV_TRAIL=0"
expect "DEV_PORTS published on loopback" "127.0.0.1:3000:3000"
expect "second port" "127.0.0.1:8080:8080"
expect "DEV_SKIP_UPDATE passed" "DEV_SKIP_UPDATE=1"
runup DEV_ASSETS="$T/ws" "$UP" "$T/ws/app"
expect "DEV_ASSETS mounted read-only" "$T/ws:/opt/assets:ro"
runup DEV_DOCTOR=1 "$UP" "$T/ws/app"
check "DEV_DOCTOR runs dev-doctor" "dev-doctor" "$(tail -1 <<< "$OUT")"

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "dev-up-args: all passed"

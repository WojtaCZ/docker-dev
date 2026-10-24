#!/usr/bin/env bash
# Reads a command key from .web-profile.json and executes it.
# Installed as /opt/web/run-web-task.sh and aliased to `web`.
#
# The web counterpart of the embedded fleet's `mcu` runner: one uniform,
# discoverable command surface across projects, so an agent does not have to
# infer whether this repo uses npm, pnpm, bun, composer or make.
#
#   web --list          tasks and settings in this workspace
#   web dev             run the dev server
#   web build
#   web test
#   web lint
#   web e2e
#   web migrate
#   web --init [stack]  detect the stack and write a starter .web-profile.json
#   web --print <key>   show a command without running it
#   web --schema        show the profile schema
#
# SECURITY NOTE: command strings come from a file in the workspace and are run
# with `bash -c` — arbitrary code execution from repo content. Deliberate, given
# this container is driven by an agent with --dangerously-skip-permissions and
# the container boundary is the security envelope. Do not point it at an
# untrusted repository.

set -uo pipefail

PROFILE_FILE="${WEB_PROFILE_FILE:-.web-profile.json}"
SCHEMA_FILE="${WEB_SCHEMA_FILE:-/opt/web/web-profile.schema.json}"

TASK_KEYS='["dev","build","start","test","testWatch","lint","format","typecheck","e2e","migrate","seed","deploy","clean","install"]'

die() { echo "ERROR: $*" >&2; exit 1; }

require_profile() {
    [ -f "$PROFILE_FILE" ] || die "$PROFILE_FILE not found in $(pwd).
       Create one with:  web --init"
    jq -e . "$PROFILE_FILE" >/dev/null 2>&1 || die "$PROFILE_FILE is not valid JSON."
}

get() { jq -r --arg k "$1" '.[$k] // empty' "$PROFILE_FILE"; }

scalar_env() {
    jq -r --argjson tasks "$TASK_KEYS" '
        to_entries
        | map(select(.key | startswith("_") | not))
        | map(select(.value | type == "string" or type == "number"))
        | map(select(.key as $k | $tasks | index($k) | not))
        | .[] | "\(.key)=\(.value)"
    ' "$PROFILE_FILE"
}

export_scalars() {
    local line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        export "${line%%=*}"="${line#*=}"
    done < <(scalar_env)
}

# --------------------------------------------------------------------------
# Detect the stack and emit a starter profile.
# --------------------------------------------------------------------------
do_init() {
    local pm="npm" runner="npx"

    if [ -f "$PROFILE_FILE" ]; then
        die "$PROFILE_FILE already exists — delete it first if you want to regenerate."
    fi

    if   [ -f bun.lockb ] || [ -f bun.lock ]; then pm="bun";  runner="bunx"
    elif [ -f pnpm-lock.yaml ];               then pm="pnpm"; runner="pnpm dlx"
    elif [ -f yarn.lock ];                    then pm="yarn"; runner="yarn dlx"
    elif [ -f deno.json ] || [ -f deno.jsonc ]; then pm="deno"; runner="deno run"
    fi

    local has_php="false"
    [ -f composer.json ] && has_php="true"

    echo "detected: package manager = $pm, php = $has_php"

    if [ "$pm" = "deno" ]; then
        jq -n '{
            _note: "Task runner profile read by `web <key>`. See `web --schema`.",
            stack: "deno",
            dev:   "deno task dev",
            build: "deno task build",
            test:  "deno test -A",
            lint:  "deno lint",
            format:"deno fmt",
            typecheck: "deno check ."
        }' > "$PROFILE_FILE"
    else
        jq -n --arg pm "$pm" --arg runner "$runner" --argjson php "$has_php" '{
            _note: "Task runner profile read by `web <key>`. See `web --schema`.",
            stack: $pm,
            packageManager: $pm,
            install:  ($pm + " install"),
            dev:      ($pm + " run dev"),
            build:    ($pm + " run build"),
            start:    ($pm + " run start"),
            test:     ($pm + " test"),
            lint:     ($pm + " run lint"),
            format:   ($pm + " run format"),
            typecheck:($pm + " run typecheck"),
            e2e:      ($runner + " playwright test")
        }
        + (if $php then {
            phpInstall: "composer install",
            phpTest:    "composer exec phpunit",
            migrate:    "php artisan migrate"
          } else {} end)' > "$PROFILE_FILE"
    fi

    echo "wrote $PROFILE_FILE:"
    cat "$PROFILE_FILE"
    echo
    echo "Edit it to match this project, then run: web --list"
}

run_key() {
    local key="$1" cmd rc
    cmd="$(get "$key")"
    [ -n "$cmd" ] || die "key '$key' not found in $PROFILE_FILE (try: web --list)"
    export_scalars
    bash -c "$cmd"
    rc=$?
    return "$rc"
}

do_list() {
    echo "Tasks defined in $PROFILE_FILE:"
    jq -r --argjson tasks "$TASK_KEYS" '
        to_entries
        | map(select(.value | type == "string"))
        | map(select(.key as $k | $tasks | index($k)))
        | .[] | "  \(.key)"' "$PROFILE_FILE"
    echo
    echo "Other commands defined here:"
    jq -r --argjson tasks "$TASK_KEYS" '
        to_entries
        | map(select(.key | startswith("_") | not))
        | map(select(.value | type == "string"))
        | map(select(.key as $k | $tasks | index($k) | not))
        | map(select(.value | test("^[a-z]") and (contains(" "))))
        | .[] | "  \(.key)"' "$PROFILE_FILE" 2>/dev/null || true
    echo
    echo "Settings:"
    scalar_env | sed 's/^/  /'
}

main() {
    [ $# -ge 1 ] || die "no key given. Usage: web <key> | web --list | web --init"

    case "$1" in
        -h|--help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            return 0
            ;;
        --schema)
            [ -f "$SCHEMA_FILE" ] || die "$SCHEMA_FILE not found"
            cat "$SCHEMA_FILE"
            return 0
            ;;
        --init)
            do_init
            return 0
            ;;
        --list)
            require_profile
            do_list
            return 0
            ;;
        --print)
            require_profile
            [ $# -ge 2 ] || die "--print needs a key"
            get "$2"
            return 0
            ;;
        -*)
            die "unknown option '$1' (try: web --help)"
            ;;
    esac

    require_profile
    run_key "$1"
}

main "$@"

#!/usr/bin/env bash
# Set up (or refresh) Trail-Code for the project in $1 (default: the current directory).
# Runs from the Claude SessionStart hook and from /trail-setup.
#
#   trail-ensure [dir]
#
# Contract (tests/unit/trail-ensure.sh):
#   * ALWAYS exits 0 and prints exactly one summary line; it must never break a session.
#   * Does nothing when the repo has a `.no-trail` file or DEV_TRAIL=0, when the
#     directory is / or $HOME, or when there is no git repo (and no child repos).
#   * One repo:            no .trail/  -> trail init --agents claude --yes
#                          .trail/     -> trail build
#                          (--agents/--yes are required: init writes nothing without a TTY)
#     with initialized submodules       -> trail build --follow-submodules
#     with nested non-submodule clones  -> trail build --follow-nested-repos
#   * Folder of repos (no top-level .git): trail build at the parent (Trail auto-splits)
#     plus `trail init` in each child that has no .trail/.
#   * Never runs git add/commit/push. After trail runs, names any file that was
#     already tracked and now differs, so the user sees what was touched.

set -uo pipefail

say() { echo "trail-ensure: $*"; }

dir="${1:-$PWD}"
dir="$(cd "$dir" 2>/dev/null && pwd -P)" || { say "skipped ($1 is not a directory)"; exit 0; }

if [ "${DEV_TRAIL:-1}" = "0" ] || [ -e "$dir/.no-trail" ]; then
    say "disabled (.no-trail or DEV_TRAIL=0)"
    exit 0
fi
if [ "$dir" = "/" ] || [ "$dir" = "$(cd "${HOME:-/nonexistent}" 2>/dev/null && pwd -P)" ]; then
    say "skipped ($dir is not a project)"
    exit 0
fi
command -v trail >/dev/null 2>&1 || { say "skipped (trail is not installed)"; exit 0; }

# Tracked files that differ from the index right now (to report only NEW changes).
dirty() { git -C "$1" diff --name-only 2>/dev/null | sort; }

run_trail() { # root args...   -> sets TRAIL_RC; runs in root
    local root="$1"; shift
    ( cd "$root" && trail "$@" >/dev/null 2>&1 )
    TRAIL_RC=$?
}

top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"

if [ -n "$top" ]; then
    before="$(dirty "$top")"
    flags=()
    # Initialized submodules show as "<sha> path"; uninitialized ones start with "-".
    if git -C "$top" submodule status 2>/dev/null | grep -q '^[ +U]'; then
        flags+=(--follow-submodules)
    fi
    # Plain clones inside the tree (no gitlink): .git DIRECTORIES below the top.
    if [ -n "$(find "$top" -mindepth 2 -maxdepth 4 -name .git -type d \
                   -not -path '*/node_modules/*' -not -path '*/.git/*' -print -quit 2>/dev/null)" ]; then
        flags+=(--follow-nested-repos)
    fi

    action=""
    rc=0
    if [ ! -d "$top/.trail" ]; then
        run_trail "$top" init --agents claude --yes; rc=$TRAIL_RC
        action="init"
        if [ "$rc" -eq 0 ] && [ "${#flags[@]}" -gt 0 ]; then
            run_trail "$top" build "${flags[@]}"; rc=$TRAIL_RC
            action="init+build ${flags[*]}"
        fi
    else
        run_trail "$top" build "${flags[@]}"; rc=$TRAIL_RC
        action="build${flags:+ ${flags[*]}}"
    fi

    if [ "$rc" -ne 0 ]; then
        say "trail $action failed in $top (exit $rc); continuing without it"
        exit 0
    fi
    after="$(dirty "$top")"
    changed="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . | tr '\n' ' ')"
    if [ -n "$changed" ]; then
        say "$action done in $top (nothing committed). Already-tracked files modified: ${changed% }"
    else
        say "$action done in $top (nothing committed)"
    fi
    exit 0
fi

# No repo at $dir: a folder of separate repos?
children=()
while IFS= read -r g; do children+=("$(dirname "$g")"); done < <(
    find "$dir" -mindepth 2 -maxdepth 2 \( -name .git -type d -o -name .git -type f \) 2>/dev/null | sort)
if [ "${#children[@]}" -eq 0 ]; then
    say "skipped (no git repository in $dir)"
    exit 0
fi

run_trail "$dir" build
if [ "$TRAIL_RC" -ne 0 ]; then
    say "trail build failed at $dir (exit $TRAIL_RC); continuing without it"
    exit 0
fi
inited=0
for c in "${children[@]}"; do
    [ -d "$c/.trail" ] && continue
    run_trail "$c" init --agents claude --yes
    [ "$TRAIL_RC" -eq 0 ] && inited=$((inited + 1))
done
say "build at $dir and init in $inited of ${#children[@]} child repo(s) (nothing committed)"
exit 0

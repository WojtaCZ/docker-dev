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
#   * Runs are serialised by a lock (TRAIL_ENSURE_LOCK, default /tmp/trail-ensure.lock):
#     when another run holds it, a one-shot run says so and exits 0 at once (so the
#     SessionStart hook never waits on a long `trail init`).
#
#   trail-ensure --watch [dir]
#     Started in the background by entrypoint.sh. Polls dir every
#     DEV_TRAIL_WATCH_INTERVAL seconds (default 20) and runs the one-shot mode above
#     when a repo appears (or gains/loses .trail/) mid-session: a clone into a
#     folder of repos, or a nested clone inside a repo. It waits until the clone has
#     settled (HEAD resolves, no index.lock, same set on two polls in a row) so Trail
#     never maps a half-checked-out tree. Exits at once when DEV_TRAIL=0.

set -uo pipefail

say() { echo "trail-ensure: $*"; }

if [ "${1:-}" = "--watch" ]; then
    shift
    [ "${DEV_TRAIL:-1}" = "0" ] && { say "watch disabled (DEV_TRAIL=0)"; exit 0; }
    wdir="$(cd "${1:-$PWD}" 2>/dev/null && pwd -P)" || { say "watch: ${1:-} is not a directory"; exit 0; }
    interval="${DEV_TRAIL_WATCH_INTERVAL:-20}"
    self="$(command -v "$0" 2>/dev/null || echo "$0")"
    # One line per settled repo: "<path> <has .trail?>". Empty while any repo is
    # mid-clone (no HEAD yet, or an index.lock), so an unsettled tree never triggers.
    state() {
        local depth=2 g r out=""
        git -C "$wdir" rev-parse --git-dir >/dev/null 2>&1 && depth=4
        while IFS= read -r g; do
            r="$(dirname "$g")"
            [ -e "$r/.git/index.lock" ] && { echo BUSY; return; }
            git -C "$r" rev-parse -q --verify HEAD >/dev/null 2>&1 || { echo BUSY; return; }
            out+="$r $([ -d "$r/.trail" ] && echo 1 || echo 0)"$'\n'
        done < <(find "$wdir" -mindepth 2 -maxdepth "$depth" \( -name .git -type d -o -name .git -type f \) \
                      -not -path '*/node_modules/*' 2>/dev/null | sort)
        printf '%s' "$out"
    }
    say "watching $wdir every ${interval}s"
    handled="$(state)"; prev="$handled"
    # Repos that were already there are the SessionStart hook's job, except ones
    # that still have no .trail/ and no session ever starts: give them one pass.
    if printf '%s' "$handled" | grep -q ' 0$'; then handled="__initial__"; fi
    while :; do
        sleep "$interval"
        [ "${DEV_TRAIL:-1}" = "0" ] && exit 0
        cur="$(state)"
        if [ "$cur" != BUSY ] && [ "$cur" = "$prev" ] && [ "$cur" != "$handled" ]; then
            echo "$(date '+%F %T') $(TRAIL_ENSURE_WAIT=1 "$self" "$wdir")"
            handled="$(state)"; [ "$handled" = BUSY ] && handled="$cur"
            cur="$handled"
        fi
        prev="$cur"
    done
fi

# One run at a time per container. Hook runs give up at once if busy; the watcher
# (TRAIL_ENSURE_WAIT=1) waits its turn.
lock="${TRAIL_ENSURE_LOCK:-/tmp/trail-ensure.lock}"
if command -v flock >/dev/null 2>&1 && exec 9>>"$lock" 2>/dev/null; then
    if [ "${TRAIL_ENSURE_WAIT:-0}" = "1" ]; then
        flock 9
    elif ! flock -n 9; then
        say "skipped (another trail-ensure is running; it will cover this project)"
        exit 0
    fi
fi

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
    ( cd "$root" && trail "$@" >/dev/null 2>&1 </dev/null )
    TRAIL_RC=$?
}

top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"

if [ -n "$top" ] && [ -e "$top/.no-trail" ]; then
    say "disabled (.no-trail in $top)"
    exit 0
fi

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

# A child with .no-trail must be left completely alone. A parent-level build would
# map it too, so it is skipped as soon as any child opted out; the other children are
# then handled one by one.
active=(); optedout=0
for c in "${children[@]}"; do
    if [ -e "$c/.no-trail" ]; then optedout=$((optedout + 1)); else active+=("$c"); fi
done
if [ "${#active[@]}" -eq 0 ]; then
    say "disabled (.no-trail in every child repo of $dir)"
    exit 0
fi

parent_built=0
if [ "$optedout" -eq 0 ]; then
    run_trail "$dir" build
    if [ "$TRAIL_RC" -ne 0 ]; then
        say "trail build failed at $dir (exit $TRAIL_RC); continuing without it"
        exit 0
    fi
    parent_built=1
fi

done_n=0; changed_all=""
for c in "${active[@]}"; do
    before="$(dirty "$c")"
    if [ -d "$c/.trail" ]; then
        # With a parent build the child map is already covered; alone it needs its own.
        [ "$parent_built" -eq 1 ] && continue
        run_trail "$c" build
    else
        run_trail "$c" init --agents claude --yes
    fi
    if [ "$TRAIL_RC" -eq 0 ]; then
        done_n=$((done_n + 1))
        after="$(dirty "$c")"
        new="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)"
        for f in $new; do changed_all="$changed_all ${c#"$dir"/}/$f"; done
    fi
done

msg="set up ${done_n} of ${#active[@]} child repo(s) in $dir"
[ "$parent_built" -eq 1 ] && msg="parent build done; $msg"
[ "$optedout" -gt 0 ] && msg="$msg, skipped $optedout with .no-trail (no parent build)"
msg="$msg (nothing committed)"
[ -n "$changed_all" ] && msg="$msg. Already-tracked files modified:${changed_all}"
say "$msg"
exit 0

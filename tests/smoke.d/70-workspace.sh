#!/usr/bin/env bash
# The entrypoint maps /workspace onto the per-project mount (DEV_WORKSPACE) so
# anything that hard-codes /workspace still lands in the right project.
# Runs LAST: it replaces /workspace in this throwaway container.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

echo "== /workspace follows DEV_WORKSPACE =="
# Earlier sections leave files in /workspace (e.g. .dev.db); a non-empty directory is
# deliberately never replaced, so start from an empty one.
find /workspace -mindepth 1 -delete
mkdir -p /workspaces/proj-1234abcd
got=$(DEV_WORKSPACE=/workspaces/proj-1234abcd DEV_SKIP_UPDATE=1 /usr/local/bin/entrypoint.sh readlink /workspace)
[ "$got" = "/workspaces/proj-1234abcd" ] || fail "/workspace -> [$got], expected /workspaces/proj-1234abcd"
touch /workspace/.probe && [ -f /workspaces/proj-1234abcd/.probe ] || fail "write through /workspace did not land in the project mount"
pass "/workspace is a symlink to the project mount and writable through it"

echo "== a project mounted directly at /workspace is left alone =="
cd /
sudo rm -rf /workspace && sudo mkdir /workspace && sudo chown dev:dev /workspace && touch /workspace/keep
got=$(DEV_WORKSPACE=/workspaces/proj-1234abcd DEV_SKIP_UPDATE=1 /usr/local/bin/entrypoint.sh sh -c '[ -f /workspace/keep ] && echo kept')
[ "$got" = kept ] || fail "entrypoint replaced a non-empty /workspace"
pass "non-empty /workspace untouched"

echo "section 70-workspace passed"

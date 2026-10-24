#!/usr/bin/env bash
# Run tests/unit/*.sh (or the ones named on the command line) inside a throwaway
# container, so they get jq, a real Arch userland and a non-root `dev` user even
# when the host has none of that.
#
#   bash tests/run-unit.sh                       # all unit tests
#   bash tests/run-unit.sh tests/unit/skills.sh  # one
#
# Env: DEV_TEST_IMAGE  image to run in. Default: dev-template:unify-test when it
#      exists, else dev-template-embedded-arm (any image with bash+jq works).
# The repo is mounted read-only at /repo; nothing here touches running containers.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${DEV_TEST_IMAGE:-}"
if [ -z "$IMAGE" ]; then
    if docker image inspect dev-template:unify-test >/dev/null 2>&1; then
        IMAGE=dev-template:unify-test
    else
        IMAGE=dev-template-embedded-arm
    fi
fi

if [ $# -gt 0 ]; then tests=("$@"); else tests=("$ROOT"/tests/unit/*.sh); fi

rc=0
for t in "${tests[@]}"; do
    rel="$(realpath --relative-to="$ROOT" "$t")"
    echo "== $rel (in $IMAGE) =="
    docker run --rm --entrypoint bash -e DEV_SKIP_UPDATE=1 \
        -v "$ROOT:/repo:ro" -w /repo "$IMAGE" "/repo/$rel" || rc=1
done
exit "$rc"

#!/usr/bin/env bash
# dev-doctor checks for Trail-Code. Emits STATUS|name|detail lines (OK / WARN / FAIL).

set -uo pipefail

emit() { echo "$1|$2|$3"; }
have() { command -v "$1" >/dev/null 2>&1; }

if have trail; then
    emit OK "trail" "$(trail --version 2>&1 | head -1)"
else
    emit FAIL "trail" "trail is not on PATH"
fi

if have trail-ensure; then
    emit OK "trail-ensure" "$(command -v trail-ensure)"
else
    emit FAIL "trail-ensure" "trail-ensure is not on PATH (the SessionStart hook calls it)"
fi

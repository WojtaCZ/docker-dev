#!/usr/bin/env bash
# Static checks on the devcontainer, CI workflows and docs. Plain bash + python3;
# runs on the host: bash tests/unit/static.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
fails=0
ok()  { echo "  ok  $*"; }
bad() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
has() { grep -qF -- "$2" "$1" && ok "$1 has: $2" || bad "$1 lacks: $2"; }
lacks() { grep -qF -- "$2" "$1" && bad "$1 still has: $2" || ok "$1 free of: $2"; }

DC=.devcontainer/devcontainer.json
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$DC" 2>/dev/null && ok "devcontainer.json is valid JSON" || bad "devcontainer.json is not valid JSON"
lacks "$DC" '--device=/dev/bus/usb'
has "$DC" 'source=/dev/bus/usb,target=/dev/bus/usb,type=bind'
has "$DC" 'c 189:* rmw'
has "$DC" 'c 188:* rmw'
has "$DC" '"workspaceFolder": "/workspaces/'
has "$DC" 'DEV_WORKSPACE'
for ext in marus25.cortex-debug mcu-debug.peripheral-viewer llvm-vs-code-extensions.vscode-clangd \
           ms-vscode.cmake-tools webfreak.debug esbenp.prettier-vscode bmewburn.vscode-intelephense-client \
           ms-playwright.playwright anthropic.claude-code; do
    has "$DC" "\"$ext\""
done
lacks "$DC" 'BASE_TAG'

P=.github/workflows/publish.yml
has "$P" 'schedule:'
has "$P" 'images: ghcr.io/${{ github.repository }}'
has "$P" 'merge-parity.sh repo'
has "$P" 'tests/run-unit.sh'
has "$P" 'docker compose -f compose/docker-compose.yml config'
has "$P" 'Free up runner disk space'
lacks .github/workflows/promote-stable.yml 'docker-dev-embedded'
has .github/workflows/promote-stable.yml 'schedule:'

lacks Dockerfile 'ENV CROSS_PREFIX'
if grep -nE '^(ENV|ARG)[[:space:]].*CROSS_PREFIX' Dockerfile >/dev/null; then bad "Dockerfile sets CROSS_PREFIX"; else ok "Dockerfile sets no CROSS_PREFIX"; fi

for needle in '.no-trail' 'DEV_TRAIL' 'past Claude sessions' 'dev-attach' 'DEV_STATE_DIR' \
              'mcu --cross-prefix' '/workspaces/' '.dev-components.json' 'DEV_TELINK_SDK' 'DEV_PORTS'; do
    has README.md "$needle"
done
lacks README.md 'docker-dev-embedded-base:'
for needle in 'A9' 'B9' 'Unified image'; do has WRITEUP.md "$needle"; done
has compose/docker-compose.yml 'name: docker-dev-web'
has compose/docker-compose.yml 'compose/docker-compose.yml'

[ "$fails" -eq 0 ] || { echo "$fails failure(s)" >&2; exit 1; }
echo "static: all passed"

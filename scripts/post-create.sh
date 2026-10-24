#!/usr/bin/env bash
set -euo pipefail

# Devcontainer post-create hook. Runs once after the container is created.
git config --global init.defaultBranch main
git config --global --add safe.directory '*'

echo "post-create: git defaults configured"

# The sqlite MCP server needs its database to exist (never fail the container over it).
bash /usr/local/bin/web-post-create.sh || echo "post-create: could not create .dev.db (non-fatal)" >&2

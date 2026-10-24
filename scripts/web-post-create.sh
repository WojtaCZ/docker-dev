#!/usr/bin/env bash
# Devcontainer post-create hook for the web image.
set -euo pipefail

bash /usr/local/bin/post-create.sh

# The sqlite MCP server opens /workspace/.dev.db at startup. On a fresh clone
# that file does not exist and the server fails to start, which surfaces as a
# missing tool rather than a clear error.
if [ ! -f /workspace/.dev.db ]; then
    sqlite3 /workspace/.dev.db "PRAGMA user_version = 1;"
    echo "web-post-create: created /workspace/.dev.db for the sqlite MCP server"
fi

# Keep it out of the project's git history unless the user opts in.
if [ -d /workspace/.git ] && ! grep -qs '^\.dev\.db$' /workspace/.git/info/exclude; then
    echo '.dev.db' >> /workspace/.git/info/exclude
fi

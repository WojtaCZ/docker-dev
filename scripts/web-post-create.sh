#!/usr/bin/env bash
# Creates the sqlite database the `sqlite` MCP server opens (.dev.db in the project
# directory: $1, or the current directory). Called by post-create.sh.
set -euo pipefail

dir="${1:-$PWD}"
db="$dir/.dev.db"

# The sqlite MCP server opens .dev.db at startup. On a fresh clone that file does
# not exist and the server fails to start, which surfaces as a missing tool rather
# than a clear error.
if [ ! -f "$db" ]; then
    sqlite3 "$db" "PRAGMA user_version = 1;"
    echo "web-post-create: created $db for the sqlite MCP server"
fi

# Keep it out of the project's git history unless the user opts in.
if [ -d "$dir/.git" ] && ! grep -qs '^\.dev\.db$' "$dir/.git/info/exclude"; then
    echo '.dev.db' >> "$dir/.git/info/exclude"
fi

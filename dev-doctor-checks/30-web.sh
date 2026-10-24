#!/usr/bin/env bash
# dev-doctor checks contributed by docker-dev-web.
set -uo pipefail

emit() { echo "$1|$2|$3"; }
have() { command -v "$1" >/dev/null 2>&1; }

need() {
    if have "$1"; then emit OK "$1" "$(command -v "$1")"
    else emit FAIL "$1" "not found on PATH"; fi
}

for b in php composer deno bun node npm nginx sqlite3 redis-cli chromium web; do
    need "$b"
done

have php     && emit OK "php-version"     "$(php -r 'echo PHP_VERSION;')"
have deno    && emit OK "deno-version"    "$(deno --version 2>/dev/null | head -1)"
have bun     && emit OK "bun-version"     "$(bun --version 2>/dev/null)"
have chromium && emit OK "chromium-version" "$(chromium --version 2>/dev/null | head -1)"

# DB clients. mysql/psql are clients only — nothing to connect to unless the
# compose stack is running.
for b in mysql psql; do
    if have "$b"; then emit OK "$b" "$(command -v "$b")"
    else emit WARN "$b" "client not found"; fi
done

# php extensions the skills assume
for ext in sqlite3 intl gd; do
    if php -m 2>/dev/null | grep -qix "$ext"; then
        emit OK "php-ext:$ext" "loaded"
    else
        emit WARN "php-ext:$ext" "not loaded"
    fi
done

# Chromium must actually launch headless, or the playwright MCP is useless.
if have chromium; then
    if timeout 30 chromium --headless --no-sandbox --disable-gpu \
            --dump-dom about:blank >/dev/null 2>&1; then
        emit OK "chromium-headless" "launches with --no-sandbox"
    else
        emit FAIL "chromium-headless" "cannot launch headless — the playwright MCP will not work"
    fi
fi

# The sqlite MCP opens this file at startup; if it is missing the server dies
# and the tool silently never appears.
if [ -f /workspace/.dev.db ]; then
    emit OK "sqlite-mcp-db" "/workspace/.dev.db present"
else
    emit WARN "sqlite-mcp-db" "/workspace/.dev.db missing — sqlite MCP may fail to start (run web-post-create.sh)"
fi

# Task runner
if [ -x /opt/web/run-web-task.sh ]; then
    emit OK "web-runner" "/opt/web/run-web-task.sh"
else
    emit FAIL "web-runner" "task runner missing"
fi
[ -f /opt/web/web-profile.schema.json ] \
    && emit OK "web-schema" "present" \
    || emit FAIL "web-schema" "missing"

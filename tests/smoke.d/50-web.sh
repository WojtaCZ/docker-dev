#!/usr/bin/env bash
# Smoke test for docker-dev-web. Runs INSIDE the built image.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

echo "== toolchain =="
for b in php composer deno bun node npm nginx sqlite3 redis-cli chromium \
         lighthouse web dev-doctor; do
    command -v "$b" >/dev/null || fail "missing: $b"
    pass "$b"
done
pass "php $(php -r 'echo PHP_VERSION;')"
pass "$(deno --version | head -1)"
pass "bun $(bun --version)"

echo "== php extensions =="
for ext in sqlite3 intl gd; do
    php -r "exit(extension_loaded(\"$ext\") ? 0 : 1);" || fail "php extension $ext not loaded"
    pass "php-$ext"
done

echo "== chromium launches headless =="
# --no-sandbox is required as a non-root user in a container. If this fails the
# playwright MCP is dead weight.
timeout 60 chromium --headless --no-sandbox --disable-gpu --dump-dom about:blank >/dev/null \
    || fail "chromium cannot launch headless"
pass "chromium --headless --no-sandbox"

echo "== settings layers merged =="
S="$HOME/.claude/settings.json"
[ -s "$S" ] || fail "entrypoint did not produce $S"
for server in github git context7 sequential-thinking playwright fetch sqlite; do
    jq -e --arg s "$server" '.mcpServers | has($s)' "$S" >/dev/null \
        || fail "MCP server '$server' missing from merged settings"
    pass "mcp: $server"
done

# @modelcontextprotocol/server-fetch does not exist on npm (registry 404).
# The fetch server is Python, published on PyPI as mcp-server-fetch.
[ "$(jq -r '.mcpServers.fetch.command' "$S")" = "uvx" ] \
    || fail "fetch MCP must use uvx — the npm package does not exist"
pass "fetch MCP uses uvx"

# Playwright must be told which browser to use on the command line; the
# PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH env var is not something Playwright reads.
jq -e '.mcpServers.playwright.args | index("--executable-path")' "$S" >/dev/null \
    || fail "playwright MCP does not pass --executable-path"
jq -e '.mcpServers.playwright.args | index("/usr/bin/chromium")' "$S" >/dev/null \
    || fail "playwright MCP does not point at the system chromium"
jq -e '.mcpServers.playwright.args | index("--no-sandbox")' "$S" >/dev/null \
    || fail "playwright MCP missing --no-sandbox"
pass "playwright MCP wired to the system chromium"

while IFS=$'\t' read -r name cmd; do
    [ -n "$name" ] || continue
    command -v "$cmd" >/dev/null || fail "MCP '$name' needs '$cmd', not on PATH"
done < <(jq -r '.mcpServers | to_entries[] | "\(.key)\t\(.value.command)"' "$S")
pass "every MCP launcher resolves"

echo "== web design plugins =="
plugins=$(claude plugin list 2>/dev/null)
for p in frontend-design@claude-plugins-official modern-web-guidance@claude-plugins-official \
         chrome-devtools-mcp@claude-plugins-official impeccable@impeccable; do
    grep -q "$p" <<<"$plugins" || fail "plugin $p not installed"
    jq -e --arg p "$p" '.enabledPlugins[$p] == true' "$S" >/dev/null \
        || fail "plugin $p not enabled in merged settings"
    pass "plugin: $p"
done

# The chrome-devtools-mcp plugin launches Chrome stable by default, which is not
# in the image; its global config file must redirect it to the system chromium.
C="$HOME/.config/cd4a/config.json"
jq -e '.executablePath == "/usr/bin/chromium" and .headless == true
       and (.chromeArg | index("--no-sandbox"))' "$C" >/dev/null \
    || fail "$C does not point chrome-devtools-mcp at headless system chromium"
[ -w "$C" ] && fail "$C is writable by $(id -un); the agent could repoint the browser"
[ -w "$HOME/.config" ] || fail "$HOME/.config is not writable; the cd4a COPY made it root-owned"
pass "chrome-devtools-mcp wired to the system chromium"

echo "== claude skills =="
for s in php-modernize db-schema-review rest-api-review web-perf-audit design-tokens-setup; do
    { [ -f "$HOME/.claude/skills/$s.md" ] || [ -f "$HOME/.claude/skills/$s/SKILL.md" ]; } || fail "skill $s.md not installed"
    pass "skill: $s"
done

echo "== sqlite MCP database =="
bash /usr/local/bin/web-post-create.sh
[ -f /workspace/.dev.db ] || fail "web-post-create.sh did not create /workspace/.dev.db"
sqlite3 /workspace/.dev.db 'select 1;' >/dev/null || fail "/workspace/.dev.db is not a valid sqlite db"
pass "/workspace/.dev.db created and readable"

echo "== web task runner =="
work=$(mktemp -d); cd "$work"
web --schema | jq -e '.title' >/dev/null || fail "web --schema broken"
pass "web --schema"

# --init detects the stack from lockfiles
printf '{}' > package.json
touch bun.lockb
web --init >/dev/null
jq -e '.stack == "bun"' .web-profile.json >/dev/null || fail "web --init did not detect bun"
pass "web --init detects bun"

rm -f .web-profile.json bun.lockb
touch pnpm-lock.yaml
web --init >/dev/null
jq -e '.stack == "pnpm"' .web-profile.json >/dev/null || fail "web --init did not detect pnpm"
pass "web --init detects pnpm"

python - <<'PY'
import json
json.dump({"stack": "npm", "appName": "demo",
           "build": "echo BUILD_OK $appName",
           "test": "echo TEST_OK"}, open(".web-profile.json", "w"), indent=2)
PY
# Capture first: under pipefail, `grep -q` exits at the first match and the
# producer dies of SIGPIPE, failing the pipeline even though the match was found.
out=$(web --list)
grep -q build <<<"$out" || fail "web --list did not show tasks"
out=$(web --print build)
grep -q BUILD_OK <<<"$out" || fail "web --print broken"
out=$(web build)
grep -q 'BUILD_OK demo' <<<"$out" || fail "scalars not exported into task commands"
pass "web run + scalar export"
if web nosuchkey >/dev/null 2>&1; then fail "unknown key should exit non-zero"; fi
pass "unknown key fails loudly"

cd /; rm -rf "$work"

echo "== dev-doctor =="
dev-doctor
dev-doctor --json | jq -e '.ok == true' >/dev/null || fail "dev-doctor reported failures"
pass "dev-doctor clean"

echo
echo "section 50-web passed"

---
name: web-tooling-reference
description: "What the unified image ships for web work and how to drive it: the `web` task runner and .web-profile.json keys (web dev/build/test/lint, web --init), php/composer, node, deno, bun, nginx, chromium for Playwright (no-sandbox risk, executable path), the sqlite MCP database and the docker-compose backing services. Use when working on a web interface, a PHP or JS project, Playwright or database tooling."
---

# Web tooling reference

| Area | What is here |
|---|---|
| PHP | `php`, `php-fpm`, `php-sqlite`, `php-intl`, `php-gd`, `composer` |
| JS runtimes | `node`/`npm` (baseline), `deno`, `bun` (at `~/.bun/bin`, on `PATH`) |
| Databases | `sqlite`, `redis`, `mariadb-clients` (client only — no server), `postgresql-libs` (libs only — no server) |
| Web server | `nginx` |
| Browser | `chromium` at `/usr/bin/chromium` — the distro build, used instead of Playwright's own download (saves ~300 MB and stays pacman-patched) |

## Commands to prefer over ad-hoc shell

- **`web <key>`** — the project task runner, reading `.web-profile.json` from the
  workspace. **Use this instead of guessing whether the repo uses npm, pnpm,
  bun, composer or make.**
  - Task keys: `dev`, `build`, `start`, `test`, `testWatch`, `lint`, `format`,
    `typecheck`, `e2e`, `migrate`, `seed`, `deploy`, `clean`, `install`
  - `web --list` shows what this workspace actually defines
  - `web --init [stack]` detects the stack and writes a starter profile
  - `web --print <key>` shows a command without running it
  - `web --schema` shows the profile schema
  - Caveat: profile commands run through `bash -c`, i.e. arbitrary code
    execution from workspace content. Deliberate. Do not point it at an
    untrusted repo.
- **`dev-doctor`** — includes the web checks (`30-web.sh`).

## Playwright / Chromium

MCP servers from this layer: `playwright`, `fetch`, `sqlite`.

- `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`, `PLAYWRIGHT_BROWSERS_PATH=/usr/lib/chromium`,
  `CHROMIUM_PATH=/usr/bin/chromium`.
- `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` is **not** a variable Playwright reads —
  the executable is chosen per launch. The MCP server takes it on the command
  line; the env vars above are only hints for scripts that read them deliberately.
- `--no-sandbox` is required running as non-root in a container. Consequence: a
  hostile page has the same reach as the `dev` user inside this container.
- The `sqlite` MCP server opens `.dev.db` in the project directory (relative path, resolved
  against the session's working directory); `post-create.sh` / `web-post-create.sh` create it.
- VSCode starters: `/opt/web/vscode-templates/`.

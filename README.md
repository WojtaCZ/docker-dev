# docker-dev

One dev container for everything: ARM Cortex-M, WCH RISC-V and Telink firmware, a PC
app, and its web interface. Every toolchain, debug tool and hardware-interface tool is
baked in at build time (nothing is installed in a running container), and Claude Code
inside it picks the right tool from the project you are in.

The former `docker-dev-embedded-{base,arm,wch,telink}` and `docker-dev-web` images were
merged into this one. Design: `docs/superpowers/specs/2026-10-24-unified-dev-container-design.md`.

## Quick start

```bash
./scripts/dev-up.sh                  # builds the image, mounts $(pwd), opens a shell
./scripts/dev-up.sh ~/code/project   # a specific project
DEV_DOCTOR=1 ./scripts/dev-up.sh     # run dev-doctor and exit
```

Windows: `.\scripts\dev-up.ps1` is a WSL2 shim (probe passthrough needs Linux device
nodes); attach probes with `usbipd attach --wsl` first. VS Code: "Reopen in Container".

The project appears at `/workspaces/<name>-<hash>` (your cwd); `/workspace` is a symlink
to it. The hash keeps two folders with the same name apart, which matters because Claude's
per-project memory is keyed by that path.

## What is inside

| Area | Tools |
|---|---|
| Base | Arch Linux, `dev` user (passwordless sudo), git, gh, jq, node, python/uv, cmake, ninja, clang, multiarch gdb |
| ARM Cortex-M | `arm-none-eabi-*`, CMSIS_6, CMSIS-DSP (m0+, m3, m4f, m7f, m33f), ST device headers (16 families), STM32 SVDs |
| WCH RISC-V | xPack `riscv-none-elf-*`, `wlink`, `wchisp`, ch32fun |
| Telink TLSR8258 | runtime pieces; the compiler is a **host mount** (EULA) |
| Debug / bench | openocd, probe-rs, pyocd, st-flash, dfu-util, sigrok-cli, picocom, bluetoothctl, ALSA tools |
| Web | php, composer, deno, bun, nginx, chromium for Playwright, lighthouse, sqlite, DB clients; Claude plugins frontend-design, impeccable, modern-web-guidance, chrome-devtools-mcp |
| Docs | `docs-init` / `docs-build`: doxygen + graphviz (firmware API docs), one Markdown manual built as a mkdocs-material website and a typst PDF (via pandoc); no TeX Live. `/write-manual` in Claude |
| Trail-Code | `trail`, set up per project automatically (below) |

`dev-doctor` reports on all of it.

## How a toolchain is chosen

By project, never by container. Each component directory carries a profile:

| Marker | Runner | Cross prefix |
|---|---|---|
| `.mcu-profile.json`, `core: cortex-*` | `mcu build/flash/debugServer/size/test` | `arm-none-eabi-` |
| `.mcu-profile.json`, `core: rv32*` | `mcu ...` | `riscv-none-elf-` |
| `.mcu-profile.json`, `core: tc32` | `mcu ...` (needs the Telink SDK mounted) | `tc32-elf-` |
| `.web-profile.json` / `package.json` / `composer.json` | `web dev/build/test` (`web --init` detects the stack) | n/a |

`mcu` finds the nearest `.mcu-profile.json` upward, runs from that directory and exports
`CROSS_PREFIX` from the profile's `crossPrefix` (derived from `core`/`march` for older
profiles); `mcu --cross-prefix` prints it. There is no container-wide `CROSS_PREFIX`.

Scaffold with `/scaffold-mcu-project <arm|wch|telink> <part>`, `/stm32-new-project <part>`,
`/ch32-new-project <part>`. Skills live at user level and trigger on what you are doing,
not on the directory, so a repo with firmware and a web UI has both sets available.

**Multi-component repos** (firmware + app + web): keep each component's profile in its
own directory; Claude keeps an optional `.dev-components.json` at the root
(`[{"path":"fw","kind":"fw-arm"},{"path":"ui","kind":"web"}]`) so it need not rediscover the layout.

## Devices

`dev-up.sh` passes devices through **live**; nothing needs a restart:

- `/dev/bus/usb`, `/dev/input`, `/dev/snd` are bind-mounted live, with wildcard
  device-cgroup rules, so any probe works (libusb) regardless of vendor/product ID.
- `ttyACM*`, `ttyUSB*`, `hidraw*` are flat in `/dev`: `scripts/dev-attach.sh attach /dev/ttyUSB0`
  (or `detach`) mknods them into every running container labelled `dev.attach=1` (which
  `dev-up.sh` sets; `DEV_CONTAINER=<name>` targets just one); the udev rule from
  `sudo scripts/install-host-udev-rules.sh` does it on every hotplug.
- Bluetooth uses the host's bluetoothd through the system D-Bus socket.
- Probe permissions are a HOST concern: run the udev installer once.

## Vendor tooling (host mounts, auto-detected)

`DEV_TELINK_SDK` (`~/telink/Telink_825X_SDK` → `/opt/telink/sdk`), `DEV_CUBECLT`
(`~/st/STM32CubeCLT`), `DEV_CUBEWBA` (`~/st/cubewba`, required for STM32WBA BLE),
`DEV_ASSETS` (`/opt/assets`). Missing mounts are normal, not a fault.

## Trail-Code

`trail-ensure` runs from a SessionStart hook and sets Trail up (or refreshes it) in the
project: `trail init --agents claude --yes`, then `trail build` on later runs, with
`--follow-submodules`/`--follow-nested-repos` where the layout needs them, and one map
at the parent for a folder of separate repos. It **never commits**; it tells you which
files appeared and which already-tracked files changed. `/trail-setup` does it on demand.

Turn it off with an empty `.no-trail` file in a repo, or `DEV_TRAIL=0`. Telemetry is off
(`trail telemetry disable` at build time).

One thing to know: `trail init` reads your past Claude sessions for the repo (using Claude
under your login, so it counts toward your usage) and the review comments on the last 50
merged PRs through `gh`. None of it goes to Trail.

## Work notes

Claude keeps notes of what it is doing in `<project>/.claude-notes/` (`progress.md` for the
main session, `agents/<name>.md` per subagent), so a usage limit or a container crash does
not lose the thread: a SessionStart hook replays `progress.md` on start, resume and compact,
and a SubagentStart hook tells each subagent where to write. The folder is inside the
bind-mounted project (survives anything), added to `.git/info/exclude` (never committed,
never shows as a change). Opt out with an empty `.no-notes` file or `DEV_NOTES=0`.

## Migrating from the old images

- **Re-run `sudo scripts/install-host-udev-rules.sh`.** A host that still has the old arm
  rule installed points at the old checkout's helper (container `dev-emb-arm`); hotplug
  stops reaching the new containers until the rule is replaced.
- Containers are now named `dev-<project>-<hash>`; scripts that used `dev-emb-arm`,
  `dev-web` etc. need `DEV_CONTAINER=` or the new name.
- Old container-only Claude state (prompt history, sessions) is not migrated: copy it into
  `~/.claude-dev` (`DEV_STATE_DIR`) if you want it.
- The devcontainer now mounts the Telink SDK, CubeCLT and CubeWBA from `~/telink` and `~/st`
  (the folders are created empty if missing; `dev-doctor` then reports "not mounted").

## Persistence

Across `--rm` runs: login, `projects/` and memory (shared with the host's `~/.claude`),
and the container-private state in `DEV_STATE_DIR` (default `~/.claude-dev`: prompt
history, file-history, backups, sessions, and `tmp/` holding Claude's per-session
scratchpads, pruned after `DEV_SCRATCH_DAYS` idle days, default 14) plus `~/.trail`. Skills, commands and plugins
are baked into the image. Package caches are named volumes (`dev-cache-*`).

## Switches

| Variable | Effect |
|---|---|
| `DEV_IMAGE`, `DEV_CONTAINER` | local tag (`dev-template`) and container name (default `dev-<project>-<hash>`, so two projects can run side by side) |
| `DEV_NO_BUILD`, `DEV_NO_PULL`, `DEV_REBUILD` | skip the build / skip `--pull` / `--no-cache` |
| `DEV_NO_CACHE_VOLUMES`, `DEV_SKIP_UPDATE` | no cache volumes / skip `claude update` at start |
| `DEV_DOCTOR` | run `dev-doctor` and exit |
| `DEV_TRAIL=0` | no automatic Trail setup |
| `DEV_PORT_RANGE=20000-20019` | port range published 1:1 on 127.0.0.1 and exported into the container, so Claude runs dev servers there. Default: a per-project block of 20 in 20000-29999 from the workspace hash (printed at start); `none` disables |
| `DEV_PORTS="3000 8080"` | publish extra dev-server ports on 127.0.0.1 |
| `DEV_NO_SERVICES` | do not join the `docker-dev-web` service network |
| `DEV_PROBE=/dev/ttyXX` | one extra static device |
| `DEV_STATE_DIR` | where the container-private Claude state lives |
| `DEV_TELINK_SDK`, `DEV_CUBECLT`, `DEV_CUBEWBA`, `DEV_ASSETS` | vendor mounts |
| `DEV_PRINT=1` | print the `docker run` argv and exit |

Backing services for web work (MariaDB, Postgres, Redis, Mailpit):
`docker compose -f compose/docker-compose.yml up -d`; `dev-up.sh` then joins their network.

## Tests

```bash
bash tests/run-unit.sh                  # unit tests, in a throwaway container (the host needs no jq)
bash tests/unit/static.sh               # devcontainer/CI/doc checks
bash tests/merge-parity.sh repo         # nothing from the old images is missing (repo side)
docker run --rm -e DEV_SKIP_UPDATE=1 -v "$PWD/tests:/tests:ro" dev-template bash /tests/smoke.sh
```

`tests/parity/manifest.txt` is generated from the real old repos by
`tools/gen-parity-manifest.sh <dir-with-the-old-repos>`; `merge-parity.sh image` checks the built image.

## Adding things

Read the MAINTENANCE RULE at the end of `claude-baseline/CLAUDE.layer.md`: skills are
directories, tools get a doctor check, everything is asserted in `tests/smoke.d/`, and
the baseline memory stays under 120 lines.

## CI

`publish.yml` builds, lints, runs the parity check, unit tests and smoke test, then pushes
`ghcr.io/<owner>/docker-dev` (`latest`, branch, semver, sha). The repo was renamed from
`docker-dev-template`; the old `ghcr.io/<owner>/docker-dev-template` package is no longer updated. It also rebuilds
weekly to pick up Arch updates. `promote-stable.yml` moves `:stable` only after the
latest main build is green.

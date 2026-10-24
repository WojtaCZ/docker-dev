# Container environment

You are in the **unified docker-dev container**: one image with every toolchain
baked in at build time. Nothing is installed or built at runtime. This file is the
inventory plus a routing table; platform detail lives in skills (they trigger on
what you are doing, in any directory). Trust this list instead of searching the
filesystem.

## What is here

| Area | Tools |
|---|---|
| Base | Arch Linux (rolling; `sudo pacman -S --needed <pkg>` works but is NOT how toolchains get here), user `dev` with passwordless sudo, `git`, `gh`, `jq`, `curl`, `ssh`, `node`/`npm`, `python`/`uv`, `base-devel`, `cmake`, `ninja`, `clang` (+`clangd`, `clang-tidy`), `gdb` (multiarch) |
| ARM Cortex-M | `arm-none-eabi-*` (newlib, v8-m.main), CMSIS_6, CMSIS-DSP per core, ST device headers, STM32 SVDs |
| WCH RISC-V | `riscv-none-elf-*` (xPack), `wlink`, `wchisp`, ch32fun at `$CH32FUN_ROOT` (never export `CH32FUN`) |
| Telink TLSR8258 | runtime pieces only; the compiler is a **host mount** at `/opt/telink/sdk` (skill `telink-sdk-mount`) |
| Debug / probes | `openocd`, `probe-rs`, `pyocd`, `st-flash`, `dfu-util`, `sigrok-cli`, `picocom`/`minicom`/`socat`, `bluetoothctl` |
| Web | `php`, `composer`, `deno`, `bun`, `nginx`, `chromium` (Playwright), `sqlite`, DB clients |
| Trail-Code | `trail` (code map + learnings) |

MCP servers: `github`, `git`, `context7`, `sequential-thinking`, `fetch`, `playwright`, `sqlite`.
**Run `dev-doctor` first** when something environmental looks wrong.

## Pick the toolchain from where you are working

| You see | It is | Use |
|---|---|---|
| `.mcu-profile.json` (`core: cortex-*`) | ARM firmware | `mcu build/flash/debugServer/size/test`; prefix `arm-none-eabi-` |
| `.mcu-profile.json` (`core: rv32*`) | WCH RISC-V firmware | `mcu ...`; prefix `riscv-none-elf-` |
| `.mcu-profile.json` (`core: tc32`) | Telink firmware | `mcu ...`; prefix `tc32-elf-`; SDK must be mounted |
| `.web-profile.json`, `package.json`, `composer.json` | web | `web dev/build/test` (`web --init` detects the stack) |
| `CMakeLists.txt`/`Makefile` and none of the above | host C/C++ | `cmake`, `ninja`, `g++`/`clang++` |

- **There is no container-wide `CROSS_PREFIX`.** It belongs to the project: `mcu`
  exports it from the profile (`crossPrefix`), and `mcu --cross-prefix` prints it.
  `mcu` finds the nearest `.mcu-profile.json` upward and runs from that directory.
- **Use `mcu <key>` / `web <key>` instead of hand-built cmake/openocd/npm commands.**
  `mcu --list`, `mcu --print <key>`, `web --list` show what a project defines.
  Profile commands run through `bash -c`: do not point them at an untrusted repo.
- New firmware project: `/scaffold-mcu-project <arm|wch|telink> <part>`,
  `/stm32-new-project <part>`, `/ch32-new-project <part>`.

### Repos with several components (firmware + software + web)

Each component directory carries its own profile; run `mcu`/`web` from inside it.
At the repo root keep an optional `.dev-components.json` so you never have to
rediscover the layout: `[{"path":"fw","kind":"fw-arm"},{"path":"cli","kind":"desktop"},{"path":"ui","kind":"web"}]`
(kinds: `fw-arm fw-wch fw-telink web desktop other`). Write it when you scaffold a
component or first work in a multi-component repo; the profiles stay the source of truth.

## Trail-Code

`trail-ensure` runs automatically at session start (hook) and sets up or refreshes
Trail in the project. It never commits: tell the user which files appeared or changed.
`/trail-setup` does it on demand (e.g. a sub-project added mid-session). A `.no-trail`
file or `DEV_TRAIL=0` turns it off. Read `.trail/learnings/` before exploring unfamiliar code.

## Work notes (every session, every subagent)

A usage limit or a container crash can end a session at any moment. Keep notes in the
project so the next session continues instead of rediscovering: `<project>/.claude-notes/`
(on the host mount, untracked via `.git/info/exclude`; opt out with `.no-notes`).

- **Main session**: `.claude-notes/progress.md`, kept current, not just at the end:
  goal, done, in progress (the exact step, files, commands), next, decisions and why,
  open problems. Update it after each meaningful step and before anything long-running
  (builds, flashing, installs). Rewrite stale parts; keep it short.
- **Subagents**: each keeps `.claude-notes/agents/<name>.md` (a SubagentStart hook gives
  the name); the main session owns progress.md. When you spawn one, say what to note.
- **Start of a session**: the hook prints progress.md. If it describes unfinished work,
  say so and continue from it; check the repo (`git status`, files) before trusting it.
- Notes record work state, not secrets.

## Paths and persistence

- The project is mounted at `/workspaces/<name>-<hash>` (your cwd); `/workspace` is a
  symlink to it. Your per-project memory is keyed by that path.
- Persisted across container re-runs: login, `projects/` + memory, prompt history,
  file-history, sessions, `~/.trail`. Skills, commands and plugins are baked in.
- Vendor tooling is a read-only host mount: Telink SDK `/opt/telink/sdk`, STM32CubeCLT
  `/opt/st/clt`, STM32CubeWBA `/opt/st/cubewba`. Absent mounts are normal, not a fault.
- Devices attach while the container runs (`/dev/bus/usb`, input, ALSA live;
  `ttyACM`/`ttyUSB`/`hidraw` via `dev-attach`). udev rules are a HOST concern.

## MAINTENANCE RULE: read this before adding a skill, command or tool

This image is built from the `docker-dev` repo. When you add something,
do all of the following in the same change, or the in-container Claude will not see it:

1. **Skills are directories**: `claude-baseline/skills/<name>/SKILL.md` with `name` and
   `description` frontmatter (a bare `<name>.md` is never indexed). Make the
   description name concrete cues: chips, file names, tools, error strings.
2. Add one line to the table above only if it is a new tool or toolchain; put detail in the skill.
3. Add a `dev-doctor` check in `dev-doctor-checks/` for anything that can be missing.
4. Add it to `tests/parity/manifest.txt` (`tools/gen-parity-manifest.sh`) and assert it in `tests/smoke.d/`.
5. Keep this file under 120 lines; the smoke test enforces it.

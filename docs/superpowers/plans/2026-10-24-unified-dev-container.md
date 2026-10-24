# Unified Dev Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge `docker-dev-embedded-base/-arm/-wch/-telink` and `docker-dev-web` into `docker-dev-template` as one image with every toolchain baked in, context-driven tool selection, Trail-Code set up per project, and persistent Claude state.

**Architecture:** One Dockerfile (slow layers first), shared assets copied into `embedded/`, `web/`, `dev-doctor-checks/`, `claude-baseline/`. Toolchain choice moves from a global `CROSS_PREFIX` env var to a per-project `crossPrefix` read by the `mcu` runner. A checked-in parity manifest, generated from the real child repos, proves nothing was dropped.

**Tech Stack:** Docker (archlinux base), bash, jq, pacman, GitHub Actions. Tests are plain bash scripts in the style of the existing `tests/smoke.sh` (`fail`/`pass`, `set -euo pipefail`).

**Spec:** `docs/superpowers/specs/2026-10-24-unified-dev-container-design.md`

## Global Constraints

- Work in `~/Documents/docker-dev/docker-dev-template` on branch `unify-dev-container`. Commit after every task; end each commit message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. **Never push.**
- Children live at `~/Documents/docker-dev/docker-dev-{embedded-base,embedded-arm,embedded-telink,embedded-wch,web}` (read-only sources; never modify them or any remote). The arm source of truth for `dev-up.sh` and the Dockerfile is `~/Documents/docker-dev-embedded-arm` (has uncommitted Bluetooth changes: `bluez-utils` and the `/run/dbus/system_bus_socket` mount). Where the repos disagree with spec Appendix A, the repos win.
- **Never stop, restart, exec into with side effects, or remove the container `dev-emb-arm`, its image `dev-template-embedded-arm`, or the volumes `dev-cache-*`.** Test images are tagged `dev-template:unify-test`; test containers are named `dev-unify-test*` and run with `--rm`.
- Image published name stays `ghcr.io/wojtacz/docker-dev-template`; local default tag `dev-template`; default container name `dev`.
- No toolchain is installed or built in a running container; everything is baked at build time. The Telink SDK stays a host mount (`~/telink/Telink_825X_SDK` → `/opt/telink/sdk`, var `DEV_TELINK_SDK`); also `DEV_CUBECLT` (`~/st/STM32CubeCLT` → `/opt/st/clt`) and `DEV_CUBEWBA` (`~/st/cubewba` → `/opt/st/cubewba`).
- Pinned values copied unchanged from the children: `RISCV_GCC_VERSION=15.2.0-1`, `WLINK_VERSION=v0.1.2`, `WCHISP_VERSION=nightly`, `CH32FUN_REF=master`, `CMSIS_6_REF=v6.2.0`, `CMSIS_DSP_REF=v1.17.0`, `SVD_STM32_REF=main`, `CMSIS_SVD_REF=main`, `TLSR_TOOLS_REF=main`, `ST_FAMILIES="wba f0 f1 f3 f4 f7 g0 g4 l0 l4 l5 u5 h5 h7 wb wl"`, `DSP_CORES="cortex-m0plus cortex-m3 cortex-m4f cortex-m7f cortex-m33f"`. Build-time assertions kept: `v8-m.main` multilib, `wlink --version`, `wchisp config --help | grep -q enable-debug`, `claude plugin list | grep superpowers@claude-plugins-official`.
- No global `ENV CROSS_PREFIX`. Never export `CH32FUN`.
- Workspace mounts at `/workspaces/<name>-<hash>` with a `/workspace` symlink fallback; no hard-coded `/workspace` in scripts or MCP config.
- Trail: `ARG TRAIL_VERSION` pinned to the latest release at build time; `trail telemetry disable` run for user `dev` (not a global `DO_NOT_TRACK`); `.no-trail` file or `DEV_TRAIL=0` disables auto-setup; Trail setup never commits.
- Optional host things (`/dev/snd`, D-Bus socket, `~/.trail`, `~/telink`, `~/st/*`) missing ⇒ warn, never fail.

## Review Focus

1. Projects scaffolded by the old children have `.mcu-profile.json` with **no `crossPrefix`**: `mcu` must derive it from `core`/`toolchain` (cortex-* → `arm-none-eabi-`, rv32* → `riscv-none-elf-`, tc32 → `tc32-elf-`) instead of failing or using an empty prefix. (Task 3)
2. Mixed repo: `mcu` run from a subdirectory of a component must find the nearest `.mcu-profile.json` upward, and two components with different architectures must each get their own prefix. (Task 3)
3. Workspace paths with spaces, unicode or a trailing slash, and two folders with the same basename, must give valid, distinct `/workspaces/...` mount names. (Task 8)
4. `trail-ensure` outside a git repo, in `$HOME` or `/`, in a repo with no commits or detached HEAD, with a read-only workspace, or when `trail` itself fails: exit 0, change nothing it shouldn't, print one line. (Task 7)
5. `dev-up.sh` with none of the optional host resources present (no `/dev/snd`, no D-Bus socket, no `~/.trail`, no SDK dirs) must still produce a valid `docker run` and exit 0. (Task 8)

---

## File Structure

| Path | Responsibility |
|---|---|
| `Dockerfile` | the single image |
| `embedded/` | `run-profile-task.sh`, `profile.schema.json`, `cmake/`, `vscode-templates/`, `profiles/{arm,wch,telink,ch582f}.json`, `udev-rules/`, `scripts/{svd-find,ch58x-sdk,build-cmsis-dsp,install-host-udev-rules}.sh` |
| `web/` | `run-web-task.sh`, `web-profile.schema.json`, `vscode-templates/` |
| `compose/docker-compose.yml` | optional backing services (from web) |
| `dev-doctor-checks/` | `30-embedded.sh 30-web.sh 40-arm.sh 40-telink.sh 40-wch.sh 50-trail.sh` |
| `scripts/` | existing + `dev-attach.sh`, `web-post-create.sh`, `trail-ensure.sh`; `dev-up.sh`/`.ps1` rewritten |
| `claude-baseline/` | `settings.json`, short `CLAUDE.layer.md`, `skills/<name>/SKILL.md`, `commands/`, `agents/` |
| `tools/gen-parity-manifest.sh` | scans the children, writes `tests/parity/manifest.txt` |
| `tests/` | `smoke.sh` (union), `merge-parity.sh`, `parity/manifest.txt`, `unit/*.sh` |

Manifest line format: `kind|name|detail`. Kinds: `pkg bin dir env file skill command doctor udev mcp`.

---

### Task 1: Parity manifest generator and parity test

**Files:**
- Create: `tools/gen-parity-manifest.sh`, `tests/merge-parity.sh`, `tests/parity/manifest.txt` (generated, committed)

**Interfaces:**
- Produces: `tools/gen-parity-manifest.sh <children-dir> > tests/parity/manifest.txt`. `tests/merge-parity.sh repo` checks `file|skill|command|doctor|udev|mcp` lines against the working tree; `tests/merge-parity.sh image` (run inside the container) checks `pkg|bin|dir|env` lines with `pacman -Qq`, `command -v`, `test -d`, and `printenv`. Prints `MISSING kind|name` per gap, exits 1 if any.

- [ ] **Step 1:** Write `tools/gen-parity-manifest.sh`. `pkg` from every `pacman -S` block in the five Dockerfiles; `env` from `ENV` lines (excluding `CROSS_PREFIX`, `PATH`, `PLAYWRIGHT_*`-hints kept); `skill` from `claude-*/skills/*` (name without `.md`); `command` from `claude-*/commands/*.md`; `doctor` from `dev-doctor-checks/*`; `udev` from `udev-rules/*`; `mcp` from the `mcpServers` keys of every settings layer (de-duplicated); `bin` from the Dockerfile-installed binaries (`wlink wchisp riscv-none-elf-gcc arm-none-eabi-gcc openocd probe-rs pyocd sigrok-cli bluetoothctl php composer deno bun chromium mcu web svd-find build-cmsis-dsp ch58x-sdk trail`) ; `dir` for `/opt/{cmsis,cmsis-dsp,svd,st/cmsis,riscv,ch32fun,telink,embedded,web}`. Also reads the uncommitted arm checkout at `~/Documents/docker-dev-embedded-arm` for `bluez-utils`.
- [ ] **Step 2:** Run it: `tools/gen-parity-manifest.sh ~/Documents/docker-dev > tests/parity/manifest.txt`; expect ≥ 150 lines, and `grep -c '^skill|'` ≥ 37, `grep 'pkg|bluez-utils'` present.
- [ ] **Step 3:** Write `tests/merge-parity.sh` (modes `repo`, `image`). Run `bash tests/merge-parity.sh repo`. Expected: FAIL listing most `skill|command|doctor|udev` lines as MISSING (assets not imported yet).
- [ ] **Step 4:** Commit `tools tests/parity tests/merge-parity.sh` — "test: add merge parity manifest and checker".

### Task 2: Import shared assets, skills, commands, doctor checks, udev rules

**Files:**
- Create/copy (verbatim content, no rewriting yet): everything in the File Structure table under `embedded/`, `web/`, `compose/`, `dev-doctor-checks/`, `scripts/{dev-attach,web-post-create}.sh`, plus all `claude-*/{skills,commands,agents}` into `claude-baseline/` (flat skills stay flat until Task 6), `udev-rules/` union into `embedded/udev-rules/` (including `61-wch-isp.rules` and `90-dev-emb-attach.rules.in`), `cmake/build-cmsis-dsp.sh` and `cmake/toolchains/` into `embedded/`.
- Modify: `embedded/profiles/` gets `arm.json` (arm's `profile.json`), `wch.json`, `telink.json`, plus `ch582f.json`.

**Interfaces:**
- Produces: the files at the paths above, which Task 4 `COPY`s and Task 3 edits.

- [ ] **Step 1:** Copy files with `cp -a`; where two children ship the same file (udev rules, `run-profile-task.sh`, `profile.schema.json`, cmake helpers, vscode templates) take `embedded-base`'s and `diff` the arm/wch/telink copies against it; any difference is reported in the commit message and resolved by taking the newer (arm) version.
- [ ] **Step 2:** Run `bash tests/merge-parity.sh repo`. Expected: PASS for `file|skill|command|doctor|udev` lines; remaining MISSING lines are only `mcp` (Task 5).
- [ ] **Step 3:** Commit — "feat: import shared assets from child repos".

### Task 3: Per-project `crossPrefix` in the `mcu` runner

**Files:**
- Modify: `embedded/run-profile-task.sh`, `embedded/profile.schema.json`, `embedded/profiles/{arm,wch,telink,ch582f}.json`, `claude-baseline/commands/{scaffold-mcu-project,stm32-new-project,ch32-new-project}.md`
- Test: `tests/unit/mcu-crossprefix.sh`

**Interfaces:**
- Produces: profile key `crossPrefix` (string). `mcu` resolves the profile by walking up from `$PWD` to the first `.mcu-profile.json` (stops at `/`; `PROFILE_FILE` env still overrides). Before running any task command it exports `CROSS_PREFIX` = profile `crossPrefix`, else derived: `core` matching `^cortex-` → `arm-none-eabi-`; `^rv32` (or `march` present) → `riscv-none-elf-`; `core == tc32` → `tc32-elf-`; else empty. `mcu --export` also writes `CROSS_PREFIX=`. Scaffolding commands copy `/opt/embedded/profiles/<arm|wch|telink>.json`.

- [ ] **Step 1:** Write `tests/unit/mcu-crossprefix.sh` (fixtures in a temp dir, `mcu` = `embedded/run-profile-task.sh`, task `build` set to `echo $CROSS_PREFIX`). Assertions: explicit `crossPrefix:"foo-"` → `foo-`; profile with only `core:"cortex-m33"` → `arm-none-eabi-`; `core:"rv32ec"` → `riscv-none-elf-`; `core:"tc32"` → `tc32-elf-`; run from `<root>/fw/sub/dir` finds `<root>/fw/.mcu-profile.json`; two sibling components (`fw-arm/`, `fw-wch/`) print different prefixes; an inherited `CROSS_PREFIX=zzz-` in the environment is overridden; no profile anywhere → exit 1 with `.mcu-profile.json not found`.
- [ ] **Step 2:** Run it; expected FAIL on every assertion except the explicit one.
- [ ] **Step 3:** Implement `resolve_profile()` and `derive_cross_prefix()` in `run-profile-task.sh`; add `crossPrefix` to the schema; add `"crossPrefix"` to the four profiles (`arm-none-eabi-`, `riscv-none-elf-`, `tc32-elf-`, `riscv-none-elf-`); update the three scaffold commands.
- [ ] **Step 4:** Run the test; expected PASS. Run `bash -n embedded/run-profile-task.sh`.
- [ ] **Step 5:** Commit — "feat: per-project crossPrefix replaces global CROSS_PREFIX".

### Task 4: Unified Dockerfile and image smoke tests

**Files:**
- Modify: `Dockerfile`, `tests/smoke.sh`
- Modify: `claude-baseline/` is untouched here.

**Interfaces:**
- Consumes: Task 2 paths, Task 3 `crossPrefix`.
- Produces: image `dev-template:unify-test` with layers in spec §1 order; `/opt/embedded/{profiles,cmake,udev-rules,vscode-templates,run-profile-task.sh,profile.schema.json}`, `/usr/local/bin/{mcu,svd-find,web,build-cmsis-dsp,ch58x-sdk,trail,trail-ensure,dev-attach}`, `/opt/web/`, `/opt/dev-doctor/checks.d/*`, `/workspaces` (owned by `dev`; the `/workspace` fallback symlink is created at start by the entrypoint, Task 5), `trail` installed with `ARG TRAIL_VERSION`.

- [ ] **Step 1:** Extend `tests/smoke.sh` (append sections, same `fail`/`pass` style) with the union of the children's `tests/smoke.sh` assertions, plus: `bash /tests/merge-parity.sh image` passes; each of `arm-none-eabi-gcc riscv-none-elf-gcc` compiles a one-line program for `-mcpu=cortex-m33 -mfloat-abi=hard` and `-march=rv32ec_zicsr -mabi=ilp32e` respectively and `clang++`/`g++` for host; `ls /usr/local/bin /usr/bin | grep -E '^(arm-none-eabi|riscv-none-elf|tc32-elf)-' | sort | uniq -d` is empty (no duplicate basenames); `trail --version`; `[ -z "${CROSS_PREFIX+x}" ]`; `web --list` runs; `php -m | grep -E 'gd|intl|pdo_sqlite|sqlite3'`; `lib32-glibc` installed; `/opt/telink` owned by `dev`; `trail telemetry status` reports disabled.
- [ ] **Step 2:** Run `docker build -t dev-template:unify-test .` expecting failure or missing tools (the Dockerfile is still the old template one), then `docker run --rm -e DEV_SKIP_UPDATE=1 -v "$PWD/tests:/tests:ro" dev-template:unify-test bash /tests/smoke.sh`. Expected: FAIL.
- [ ] **Step 3:** Rewrite `Dockerfile` in spec §1 order, merging package lists (de-duplicated, one `pacman -Syu` + `-S` per layer group), enabling `[multilib]` before the shared embedded layer, keeping every pinned `ARG` and build-time assertion from Global Constraints, adding `bluez-utils`, `lib32-glibc lib32-gcc-libs`, bun install for `dev`, `npm install -g @trailhq/trail-code@${TRAIL_VERSION}` and the `trail init --help`/`trail build --help` flag checks from spec §5, `RUN trail telemetry disable` as `dev`, `groupadd -f plugdev dialout; usermod -aG dialout,uucp,tty,plugdev,lock dev`, and the web ENV block (without `CROSS_PREFIX`).
- [ ] **Step 4:** Rebuild and rerun the smoke command. Expected: all `ok`, exit 0. (First build is long; cache keeps the rest fast.)
- [ ] **Step 5:** Commit — "feat: single image with all toolchains".

### Task 5: Claude settings, short memory, post-create

**Files:**
- Modify: `claude-baseline/settings.json`, `claude-baseline/CLAUDE.layer.md`, `scripts/post-create.sh`, `scripts/entrypoint.sh`, `Dockerfile` (COPY lines only)
- Test: `tests/smoke.sh` (append)

**Interfaces:**
- Produces: `00-baseline.json` with MCP servers `github git context7 sequential-thinking fetch playwright sqlite` (playwright args `-y @playwright/mcp --browser chromium --executable-path /usr/bin/chromium --no-sandbox`; sqlite `--db-path` as the string `.dev.db`, relative to the working directory) and the `SessionStart` hook from Task 7. `CLAUDE.layer.md` ≤ 120 lines: inventory, marker-file routing table, runner rules (`mcu`, `web`, `dev-doctor`), mounted-SDK paths, Trail rule, "skills hold platform detail". `post-create.sh` calls `web-post-create.sh` (creates `.dev.db` in `$PWD`). The memory layer also documents the optional `.dev-components.json` (`[{"path":"fw","kind":"fw-arm"},…]`, kinds `fw-arm fw-wch fw-telink web desktop other`) that Claude writes for multi-component repos. `entrypoint.sh`: when `DEV_WORKSPACE` is set (by `dev-up.sh`, Task 8) it runs `sudo ln -sfn "$DEV_WORKSPACE" /workspace`.

- [ ] **Step 1:** Append smoke assertions (replace the old `/workspace` check: run with `-e DEV_WORKSPACE=/workspaces/t -v /tmp/t:/workspaces/t` and assert `readlink /workspace` equals `/workspaces/t` and it is writable; and `grep -q 'dev-components.json' ~/.claude/CLAUDE.md`): all seven MCP servers present in merged settings; every MCP launcher resolves on `PATH` (existing loop); `wc -l < ~/.claude/CLAUDE.md` ≤ 120; `grep -q '\.mcu-profile\.json' ~/.claude/CLAUDE.md` and `grep -q '\.web-profile\.json'`; `grep -rn '/workspace[^s]' ~/.claude-layers /usr/local/bin/web-post-create.sh` finds nothing.
- [ ] **Step 2:** Run smoke; expected FAIL on MCP and line-count checks.
- [ ] **Step 3:** Write the settings union, the short memory layer (move ARM project-layout tree, CMSIS-DSP usage, CH58x flow and Telink mount text out of it — Task 6 turns them into skills), update `post-create.sh`.
- [ ] **Step 4:** Rebuild, rerun smoke; expected PASS. Run `bash tests/merge-parity.sh repo`; expected PASS including `mcp`.
- [ ] **Step 5:** Commit — "feat: unified Claude settings and short baseline memory".

### Task 6: Skills in directory form

**Files:**
- Modify: every flat `claude-baseline/skills/<name>.md` → `claude-baseline/skills/<name>/SKILL.md` (content unchanged, frontmatter added)
- Create: `claude-baseline/skills/{arm-project-layout,telink-sdk-mount,embedded-tooling-reference}/SKILL.md` (text moved from the old memory layers)
- Test: `tests/unit/skills.sh`

**Interfaces:**
- Produces: each skill dir has `SKILL.md` starting with `---`, `name:` equal to the directory, `description:` ≥ 60 chars naming at least two concrete cues (chip, file, tool or command). No flat `*.md` files remain directly under `skills/`.

- [ ] **Step 1:** Write `tests/unit/skills.sh` asserting the interface above for every entry and that the parity manifest's `skill|` names all exist as directories.
- [ ] **Step 2:** Run it; expected FAIL (flat files).
- [ ] **Step 3:** Convert mechanically, writing each `description` from the skill's own opening paragraph plus cues (e.g. `stm32-clock-config`: "RCC setup on STM32 (HSE/PLL, flash latency before raising SYSCLK); use when editing clock init or `system_stm32*.c`"). Create the three new skills from the removed memory text.
- [ ] **Step 4:** Run `bash tests/unit/skills.sh` and `bash tests/merge-parity.sh repo`; expected PASS.
- [ ] **Step 5:** Commit — "feat: directory-form skills with context cues".

### Task 7: `trail-ensure`, `/trail-setup`, session hook

**Files:**
- Create: `scripts/trail-ensure.sh`, `claude-baseline/commands/trail-setup.md`, `dev-doctor-checks/50-trail.sh`
- Modify: `claude-baseline/settings.json` (hook), `Dockerfile` (COPY + symlink `/usr/local/bin/trail-ensure`)
- Test: `tests/unit/trail-ensure.sh`

**Interfaces:**
- Produces: `trail-ensure [dir]` (default `$PWD`), always exit 0, prints exactly one summary line. Behaviour: `.no-trail` file or `DEV_TRAIL=0` → no-op; not inside a git work tree and no child git repos → no-op; no `.trail/` → `trail init --agents claude --yes`; `.trail/` present → `trail build`; superproject with initialized submodules → add `--follow-submodules`; repo containing nested non-submodule repos → `--follow-nested-repos`; folder of repos with no top `.git` → `trail build` at the parent and `trail init --agents claude --yes` in each child; afterwards prints `git diff --stat` of previously tracked files that changed; never runs `git commit/add/push`. Hook: `{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"trail-ensure"}]}]}}`.

- [ ] **Step 1:** Write `tests/unit/trail-ensure.sh` with a stub `trail` first on `PATH` that appends its arguments to `$TRAIL_LOG`, using temp git fixtures. Cases: plain repo → log is `init --agents claude --yes`; repo with `.trail/` → `build`; `.no-trail` → empty log; `DEV_TRAIL=0` → empty log; non-git dir → empty log; submodule fixture → `build --follow-submodules`; nested-repo fixture → `build --follow-nested-repos`; folder of two repos → `build` at parent plus one `init` per child; stub exits 1 → `trail-ensure` still exits 0; repo with no commits and a detached-HEAD repo → exit 0; read-only dir → exit 0; `git rev-parse HEAD` identical before/after in a repo with a pre-existing tracked `.mcp.json` that the stub modifies, and the output mentions `.mcp.json`; `$HOME` and `/` → no-op.
- [ ] **Step 2:** Run it; expected FAIL (script missing).
- [ ] **Step 3:** Implement `scripts/trail-ensure.sh`; write `/trail-setup` (runs `trail-ensure`, reports changed files, tells the user nothing was committed); write `50-trail.sh` (`OK|trail|<version>`); add the hook to settings.
- [ ] **Step 4:** Run the test; expected PASS. Rebuild image, run smoke (adds `trail-ensure` on `PATH`, hook present in merged settings).
- [ ] **Step 5:** Commit — "feat: Trail-Code auto-setup per project".

### Task 8: Unified `dev-up.sh`

**Files:**
- Modify: `scripts/dev-up.sh` (start from `~/Documents/docker-dev-embedded-arm/scripts/dev-up.sh` including its uncommitted Bluetooth block)
- Test: `tests/unit/dev-up-args.sh`

**Interfaces:**
- Produces: env `DEV_PRINT=1` prints the final `docker run …` argv one per line and exits 0 without running docker (build skipped). Workspace mount name function `workspace_mount_name <abs-path>` → `<sanitised-basename>-<first 8 hex of sha256(abs-path)>` (sanitise to `[A-Za-z0-9._-]`, trailing slash stripped). Default `DEV_IMAGE=dev-template`, `DEV_CONTAINER=dev`. New env: `DEV_TRAIL=0` (passed through), `DEV_TELINK_SDK`. All arm env switches retained.

- [ ] **Step 1:** Write `tests/unit/dev-up-args.sh` using fake `HOME`, fake `/proc/devices` via `DEV_PROC_DEVICES` override, and `DEV_PRINT=1`. Assertions: output contains `--device-cgroup-rule=c 189:* rmw`, hidraw, ttyACM (166), **ttyUSB (188)**, input (13), alsa (116); `-v /dev/bus/usb:/dev/bus/usb`; the D-Bus socket mount when the socket exists (`DEV_DBUS_SOCKET` override); `-v <ws>:/workspaces/<name>-<hash>` and `-w /workspaces/<name>-<hash>`; Claude mounts for `.claude.json`, `.credentials.json`, `projects`, `history.jsonl`, `file-history`, `backups`, `sessions`, `session-env`, `shell-snapshots`; `~/.trail` mount; SDK mounts only when those dirs exist; Review Focus 3 cases: `"/tmp/my proj/"`, `"/tmp/ünï"`, and two different dirs both named `app` give valid, different names; Review Focus 5: with no optional resources the command still prints a valid argv, exit 0, warnings on stderr only.
- [ ] **Step 2:** Run it; expected FAIL.
- [ ] **Step 3:** Implement: add `DEV_PRINT`, `workspace_mount_name`, the ttyUSB rule, Telink SDK auto-mount, persisted-state mounts (create missing host files/dirs first), `~/.trail`, `-w`, join the `docker-dev-web` network when it exists, extra volumes `dev-cache-composer` and `dev-cache-bun`, and the `DEV_TRAIL` env passthrough and `-e DEV_WORKSPACE=/workspaces/<name>-<hash>`; extend the background mirror loop to `ttyUSB*`.
- [ ] **Step 4:** Run the test; expected PASS. Run `bash -n scripts/dev-up.sh`.
- [ ] **Step 5:** Commit — "feat: unified dev-up.sh".

### Task 9: `dev-attach.sh`, udev template, `dev-up.ps1`

**Files:**
- Modify: `scripts/dev-attach.sh`, `embedded/udev-rules/90-dev-emb-attach.rules.in`, `embedded/scripts/install-host-udev-rules.sh`, `scripts/dev-up.ps1`
- Test: `tests/unit/dev-attach.sh`

**Interfaces:**
- Produces: `dev-attach.sh` default `DEV_CONTAINER=dev`; accepts `/dev/ttyACM*`, `/dev/ttyUSB*`, `/dev/hidraw*` (already); udev template covers `ttyUSB[0-9]*` add and remove for `SUBSYSTEM=="tty"`; `dev-up.ps1` mirrors the switches of `dev-up.sh` (names only; Windows path logic unchanged).

- [ ] **Step 1:** Write `tests/unit/dev-attach.sh` with a stub `docker` on `PATH` (records args; `inspect` returns `true`) and a fake char device via `DEV_STAT_OVERRIDE` env. Assertions: `attach /dev/ttyUSB0` issues a `docker exec -u root dev sh -c … mknod` with the node's major/minor; `detach /dev/ttyUSB0` issues `rm -f`; non-matching node `/dev/null` is skipped with `skip:`; container not running → exit 0 with `info:`; `grep -c 'ttyUSB' embedded/udev-rules/90-dev-emb-attach.rules.in` ≥ 2.
- [ ] **Step 2:** Run it; expected FAIL on the udev count and any default-name assertion.
- [ ] **Step 3:** Update the three scripts, the rules template, and the PowerShell script (add `DEV_TELINK_SDK`, `DEV_CUBECLT`, `DEV_CUBEWBA`, `DEV_TRAIL`, new default names, `/workspaces/<name>-<hash>` mount).
- [ ] **Step 4:** Run the test; expected PASS. `bash -n` the shell scripts; if `pwsh` exists, `pwsh -NoProfile -Command '[void][scriptblock]::Create((Get-Content -Raw scripts/dev-up.ps1))'`.
- [ ] **Step 5:** Commit — "feat: ttyUSB attach, unified default names, ps1 parity".

### Task 10: devcontainer, CI, docs

**Files:**
- Modify: `.devcontainer/devcontainer.json`, `.github/workflows/publish.yml`, `.github/workflows/promote-stable.yml` (only if names change — they should not), `README.md`, `WRITEUP.md`
- Test: `tests/unit/static.sh`

**Interfaces:**
- Produces: devcontainer with live passthrough (`-v /dev/bus/usb:/dev/bus/usb`, cgroup rules via `runArgs`), `workspaceFolder` following the new mount, union of VS Code extensions from all children; `publish.yml` builds the single image and keeps the scheduled rebuild web had.

- [ ] **Step 1:** Write `tests/unit/static.sh`: `jq -e . .devcontainer/devcontainer.json` (after stripping comments if any); no `--device=/dev/bus/usb` string; extensions include `marus25.cortex-debug`, `llvm-vs-code-extensions.vscode-clangd`, `ms-vscode.cmake-tools`; workflow YAML has a `schedule:` key and image name `ghcr.io/wojtacz/docker-dev-template`; `grep -rn 'CROSS_PREFIX=' Dockerfile` empty; README mentions `.no-trail`, `DEV_TRAIL`, and the Trail session/PR reading note.
- [ ] **Step 2:** Run it; expected FAIL.
- [ ] **Step 3:** Make the edits; rewrite README for the single image (usage, device attach, Trail, persistence, mounted SDKs); carry any still-open defects from the children's `WRITEUP.md` files into the template's WRITEUP as known issues.
- [ ] **Step 4:** Run `bash tests/unit/static.sh`; expected PASS.
- [ ] **Step 5:** Commit — "docs/ci: devcontainer, workflow and docs for the single image".

### Task 11: End-to-end verification

**Files:** none new (fixes go to whichever task owns the failure).

- [ ] **Step 1:** Run all unit tests: `for t in tests/unit/*.sh; do bash $t || exit 1; done`. Expected: all pass.
- [ ] **Step 2:** `bash tests/merge-parity.sh repo`, then rebuild from scratch the arm-relevant layers is not needed; run `docker run --rm -e DEV_SKIP_UPDATE=1 -v "$PWD/tests:/tests:ro" dev-template:unify-test bash /tests/smoke.sh` and `... bash /tests/merge-parity.sh image`. Expected: exit 0, no `MISSING`.
- [ ] **Step 3:** Start a throwaway container with the real script: `DEV_PRINT=1 scripts/dev-up.sh ~/Documents/programovani` inspect the argv; then `DEV_NO_BUILD=1 DEV_IMAGE=dev-template:unify-test DEV_CONTAINER=dev-unify-test DEV_DOCTOR=1 scripts/dev-up.sh /tmp/unify-ws` and confirm `dev-doctor` exit 0.
- [ ] **Step 4:** Confirm the original is untouched: `docker ps --format '{{.Names}} {{.Status}}'` still lists `dev-emb-arm` as `Up`, and `docker image inspect dev-template-embedded-arm` still resolves.
- [ ] **Step 5:** Confirm the backup at `~/Documents/docker-dev/arm-container-state-2026-10-24/` is intact, then `git status` clean and `git log --oneline` shows one commit per task. Report: image size, build time, anything in the parity manifest explicitly waived (none expected), and the manual hardware checklist the user must run (attach a probe live, `dev-attach.sh attach /dev/ttyUSB0`, `bluetoothctl` through the D-Bus socket, `trail-ensure` in a real project).

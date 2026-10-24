---
name: embedded-tooling-reference
description: "What the unified image ships for embedded work and how to drive it: the mcu task runner and .mcu-profile.json keys, svd-find, shared CMake helpers (embedded_hardening), udev rules, plus the ARM, WCH and Telink tool inventories (arm-none-eabi, riscv-none-elf, wlink, wchisp, openocd, probe-rs, pyocd, CMSIS, SVD stores). Use when you need to know which tool or path exists, or how to build, flash or debug a firmware project."
---

# Embedded tooling reference

Debug and analysis tools shared by every target: `openocd`, `probe-rs`, `pyocd`
(+ `cmsis-pack-manager`), `st-info`/`st-flash`, `dfu-util`, `gdb` (Arch's gdb IS multiarch;
there is no `gdb-multiarch`), `cmake`, `ninja`, `make`, `meson`, `ccache`, `clang` (ships
`clangd`, `clang-tidy`, `clang-format`), `lld`, `llvm`, `cppcheck`, `gtest`, `catch2`, `gcovr`,
`lcov`, `picocom`, `minicom`, `screen`, `socat` (`tio` is NOT installed), `usbutils`, `libusb`,
`hidapi`, `sigrok-cli`, `bluez-utils`, `alsa-utils`.

## Commands to prefer over ad-hoc shell

- **`mcu <key>`** — the project task runner. Reads `.mcu-profile.json` from the
  workspace and runs the command stored under `<key>`. **Use this instead of
  reconstructing cmake/openocd invocations by hand.**
  - Task keys: `build`, `buildDebug`, `clean`, `flash`, `erase`, `reset`,
    `serial`, `debugServer`, `rtt`, `size`, `test`, `hostTest`
  - `mcu --list` shows the keys and settings actually defined here
  - `mcu --print <key>` shows a command without running it
  - `mcu --export` writes scalar keys to `.vscode/.profile.env` for `launch.json`
  - `size` and `test` are built in: `size` enforces `.sizeBudget`; `test`
    flashes, captures target output and asserts on `.testPass`/`.testFail`
  - Caveat: profile command strings run through `bash -c`, i.e. arbitrary code
    execution from workspace content. Deliberate. Do not point it at an
    untrusted repo.
- **`svd-find <part>`** — locate a `.svd` for register-level reasoning. Searches
  the bundled stores, and `svd-find --pack <part>` pulls from ST's CMSIS-Pack
  via pyocd for parts neither store carries.
- **`dev-doctor`** — includes embedded checks (`30-embedded.sh`) on top of the
  baseline ones.

## Paths and env vars

| Var / path | Meaning |
|---|---|
| `$SVD_STORE` = `/opt/svd` | SVD store. `cmsis-svd-data/` is the multi-vendor set; leaves add vendor mirrors |
| `$PYOCD_HOME` = `/opt/pyocd` | pyocd packs land here (world-writable, so `dev` can install packs) |
| cross prefix | **Per project, not a container variable.** `mcu` exports `CROSS_PREFIX` from the profile's `crossPrefix` (`arm-none-eabi-`, `riscv-none-elf-`, `tc32-elf-`; derived from `core`/`march` for older profiles); `mcu --cross-prefix` prints it. Use it instead of hardcoding a triple |
| `/opt/embedded/cmake/` | Shared CMake helpers (below) |
| `/opt/embedded/vscode-templates/` | `tasks.json` + `launch.json` starters |
| `/opt/embedded/profile.schema.json` | `.mcu-profile.json` schema; also `mcu --schema` |
| `/opt/embedded/udev-rules/` | **Inert here** — udev does not run in a container. Shipped so `install-host-udev-rules.sh` can install them on the HOST. Probe permission problems are a host-side fix |

## Shared CMake helpers

`include(/opt/embedded/cmake/embedded-common.cmake)` (has an `include_guard`,
safe to include repeatedly) provides:

- `embedded_hardening(<target>)` — the fleet's standard bare-metal C++ flags:
  C++20, no exceptions/RTTI/threadsafe-statics, `-ffunction-sections`
  `-fdata-sections` + `--gc-sections`, a warning set including `-Wconversion`
  and `-Wdouble-promotion`, a linker map and `--print-memory-usage`,
  `nano.specs`/`nosys.specs`. Call this rather than hand-rolling flags.
- `find_cmsis_dsp(<core> <outvar>)` — ARM leaf only; see the ARM layer.

`/opt/embedded/cmake/host-test.cmake` covers host-side unit tests.

## ARM inventory

| Area | What is here |
|---|---|
| Toolchain | `arm-none-eabi-gcc`/`g++`, `arm-none-eabi-newlib`, `arm-none-eabi-gdb`, `arm-none-eabi-binutils`. The build asserts newlib has a `v8-m.main` multilib, so Cortex-M33 hard-float links work |
| CMSIS core | `$CMSIS_DIR` = `/opt/cmsis` (CMSIS_6, header-only: `core_cm*.h`, `cmsis_gcc.h`, ARMv8-M TrustZone helpers) |
| CMSIS-DSP | `$CMSIS_DSP_DIR` = `/opt/cmsis-dsp`, **one static library per core** |
| ST device headers | `$STM32_CMSIS_DIR` = `/opt/st/cmsis/<family>/` — headers, startup, GCC linker templates. Families: `wba f0 f1 f3 f4 f7 g0 g4 l0 l4 l5 u5 h5 h7 wb wl`. **Apache-2.0 CMSIS device files, NOT the HAL** |
| SVDs | `/opt/svd/stm32` (modm-io mirror: C0/G0/G4/H5/H7/L5/U5/WBA5/WB0/N6) searched before the multi-vendor store. **WBA6x is in neither** — use `svd-find --pack stm32wba65` |
| CMake toolchain file | `/opt/embedded/cmake/toolchains/arm-none-eabi.cmake` — sets `ARM_CORE`, `ARM_FPU` and derives `CMSIS_DSP_CORE` |
| Default profile | `/opt/embedded/profile.json` (STM32F407VG starter, copied by `/scaffold-mcu-project`) |

#### CMSIS-DSP — opt-in, prebuilt per core

Prebuilt: `cortex-m0plus`, `cortex-m3`, `cortex-m4f`, `cortex-m7f`,
`cortex-m33f`. A cortex-m4 (ARMv7E-M) archive is the **wrong artefact** for a
cortex-m33 (ARMv8-M) target, which is why each core has its own.

Nothing links it by default. To add it to a project, use the
`cmsis-dsp-cpp` skill — it has the exact `CMakeLists.txt` edits, the
`find_cmsis_dsp()` contract (it sets both `DSP_LIB` and
`DSP_LIB_INCLUDE_DIRS`), and the flag-match rules.

For a core that is not prebuilt: `build-cmsis-dsp <core>` (e.g. `cortex-m55`
for Helium, or soft-float `cortex-m4`); no arguments lists the known cores. It
generates the per-core toolchain file CMSIS-DSP does not ship, builds, and
installs into the layout `find_cmsis_dsp()` reads. Each variant records what it
was built with in `lib/<core>/flags.cmake` and `lib/<core>/build-attributes.txt`
— read those first when a link fails on architecture or float-ABI mismatch.

## WCH inventory

| Area | What is here |
|---|---|
| Toolchain | `riscv-none-elf-gcc`/`g++`/`gdb` + newlib, xPack prebuilt under `/opt/riscv`, symlinked onto `PATH`. Covers RV32EC through RV32IMAC |
| Probe flashing | `wlink` — WCH-Link flash, debug, and a GDB server |
| **No-probe flashing** | `wchisp` — drives the factory USB ISP bootloader every CH32V part exposes. This is the difference between "needs a WCH-Link" and "needs a USB cable". Reach for it when no probe is attached |
| Bare-metal scaffolding | `$CH32FUN_ROOT` = `/opt/ch32fun` (`$CH32V_FUN` and `/opt/ch32v003fun` are aliases). **Never export `CH32FUN`** � ch32fun.mk reads it as its own `ch32fun/` subdir — cnlohr's ch32fun: header + minimal startup, no MounRiver, no vendor HAL. Covers the whole CH32V/CH32X range |
| CMake toolchain file | `/opt/embedded/cmake/toolchains/riscv-none-elf.cmake` |
| **CH582F / CH58x** | USB-only flow: hold BOOT, plug in, `wchisp` (`4348:55e0`). Profile `/opt/embedded/profiles/ch582f.json`; ch32fun `TARGET_MCU:=CH582F` (RV32IMAC, 448 KB flash, 32 KB RAM). `ch58x-sdk` fetches WCH's official EVT SDK (BLE stack) on demand |
| Default profile | `/opt/embedded/profile.json` (CH32V003F4P6, `rv32ec`, probe/flashTool `wlink`) |

Everything in the embedded layer above is present too — `mcu`, `svd-find`,
`openocd`, `probe-rs`, `gdb`, `clang`, the shared CMake helpers.

## Telink inventory

| Area | What is here |
|---|---|
| Cross compiler | **Mounted, not installed** — `/opt/telink/sdk/tools/tc32/bin/tc32-elf-*` |
| Multilib runtime | `lib32-glibc`, `lib32-gcc-libs` (what the 32-bit tc32 blob needs) |
| Build | `make`, `cmake`, `ninja`, `meson` |
| Debug / flash | `gdb`, `openocd`, `probe-rs`, `stlink`, `dfu-util` |
| SWS flashing | `$TLSR_TOOLS` = `/opt/telink/tlsr-tools` (pvvx/TLSRPGM). **Needs dedicated programmer hardware** — a TB-04-KIT or TLSR8269 running TLSRPGM firmware, wired PD3→RESET, PD4↔SWS, PB4→Power. A bare USB-serial adapter is not enough. Telink's own BDT is Windows-GUI only |
| Serial | `picocom`, `screen`, `minicom`, `socat`, `python-pyserial` |
| Host tests | `gtest`, `catch2`, `gcovr` |
| Task runner | `mcu` — same runner and task keys as the embedded layer |
| CMake helpers | `/opt/embedded/cmake/embedded-common.cmake`, `host-test.cmake` (verbatim copies owned by `docker-dev-embedded-base`; resync with that repo's `scripts/sync-shared-assets.sh`) |

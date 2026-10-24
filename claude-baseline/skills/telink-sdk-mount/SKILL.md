---
name: telink-sdk-mount
description: "Telink TLSR8258 (tc32) builds: the compiler is NOT in the image, it comes from the host-mounted Telink SDK at /opt/telink/sdk (tc32-elf-gcc under tools/tc32/bin). Use when tc32-elf-gcc is not found, when a Telink build fails with 'Telink SDK not mounted', or before starting any TLSR8258 firmware work."
---

# Telink SDK mount


The Telink SDK is EULA-restricted and not redistributable, so the image ships a
**mount point**, not a compiler:

```
-v ~/telink/Telink_825X_SDK:/opt/telink/sdk:ro
```

`PATH` already includes `/opt/telink/sdk/tools/tc32/bin`, where the SDK's
`tc32-elf-gcc` blob lives. With nothing mounted there, `tc32-elf-gcc` simply
does not resolve — that is expected, not a broken image. Run
`/telink-sdk-check` (or `dev-doctor`) to confirm the mount before diagnosing
build failures.

| Area | What is here |
|---|---|
| Cross compiler | **Mounted, not installed** — `/opt/telink/sdk/tools/tc32/bin/tc32-elf-*` |
| Multilib runtime | `lib32-glibc`, `lib32-gcc-libs` (what the 32-bit tc32 blob needs) |
| Build | `make`, `cmake`, `ninja`, `meson` |
| Debug / flash | `gdb`, `openocd`, `probe-rs`, `stlink`, `dfu-util` |
| SWS flashing | `$TLSR_TOOLS` = `/opt/telink/tlsr-tools` (pvvx/TLSRPGM). **Needs dedicated programmer hardware** — a TB-04-KIT or TLSR8269 running TLSRPGM firmware, wired PD3→RESET, PD4↔SWS, PB4→Power. A bare USB-serial adapter is not enough. Telink's own BDT is Windows-GUI only |
| Serial | `picocom`, `screen`, `minicom`, `socat`, `python-pyserial` |
| Host tests | `gtest`, `catch2`, `gcovr` |
| Task runner | `mcu` (same task keys as every embedded target) |

## Profile

Scaffold with `/scaffold-mcu-project telink` (copies `/opt/embedded/profiles/telink.json`,
which sets `core: tc32` and `crossPrefix: tc32-elf-`). There is no first-class CLI flasher for
TC32 and no in-container GDB server: see `$TLSR_TOOLS` (pvvx/TLSRPGM, needs SWire programmer
hardware) or flash from the host with Telink's BDT. Run `/telink-sdk-check` first.

`dev-up.sh` mounts `~/telink/Telink_825X_SDK` automatically (or set `DEV_TELINK_SDK=<path>`).

Create a WCH CH32V/CH32X project from a part number. Arguments: $ARGUMENTS

Usage: `/ch32-new-project <part-number> [make|cmake]`
Examples: `/ch32-new-project CH32V003F4P6`, `/ch32-new-project CH582F`, `/ch32-new-project CH32V203C8T6 cmake`

Build system defaults to `make` (ch32fun's own, the well-trodden path). Pass
`cmake` for the CMake flow, which gives you the same `tasks.json` / `launch.json`
experience as the arm leaf.

## Steps

### 1. Resolve the part

If no part number was given, ask and stop — `-march`/`-mabi` cannot be guessed.
Use the **`ch32v-family-differences`** skill. The V003 is not representative of
the range; do not carry V003 assumptions to a V203.

| Part | `march` | `mabi` | Flash | SRAM | ch32fun define |
| --- | --- | --- | --- | --- | --- |
| CH32V003 | `rv32ec_zicsr` | `ilp32e` | 16 KB | 2 KB | `CH32V003` |
| CH32V103 | `rv32imac_zicsr` | `ilp32` | 32–64 KB | 10–20 KB | `CH32V10x` |
| CH32V203 | `rv32imac_zicsr` | `ilp32` | 32–64 KB | 10–20 KB | `CH32V20x` |
| CH32V303 | `rv32imafc_zicsr` | `ilp32f` | 62–128 KB | 32 KB | `CH32V30x` |
| CH32X033 | `rv32imac_zicsr` | `ilp32` | 62 KB | 20 KB | `CH32X03x` |
| CH582F (CH58x) | `rv32imac` | `ilp32` | 448 KB | 32 KB | `TARGET_MCU:=CH582F` |

**CH58x/CH59x/CH57x are a different flow** � read the `ch58x-sdk-choices` and `ch58x-usb-isp`
skills first. Use `/opt/embedded/profiles/ch582f.json` as `.mcu-profile.json` (flash with
`wchisp` over USB, no probe), copy `$CH32V_FUN/examples_ch5xx/blink` as the base and set
`TARGET:=firmware`, `TARGET_MCU:=CH582F` and `flash : ; wchisp flash $(TARGET).bin`. Skip
steps 3b-4 (ch32fun generates the linker script). BLE needs `ch58x-sdk` (official EVT).

`ilp32e` and `ilp32` are **not** link-compatible, and RV32EC has no hardware
multiply. Getting this pair wrong produces a binary that links and then executes
illegal instructions.

### 2. Scaffold

```bash
mkdir -p .vscode src
cp /opt/embedded/vscode-templates/tasks.json  .vscode/tasks.json
cp /opt/embedded/vscode-templates/launch.json .vscode/launch.json
cp /opt/embedded/profile.json                 .mcu-profile.json   # CH582F: /opt/embedded/profiles/ch582f.json
```

Set `chip`, `core`, `march`, `mabi` and a real `sizeBudget` from the table
above, then delete the `_chips` and unused `_*_variant` blocks.

For a CMake project, take the commands from the `_cmake_variant` block already
in the profile. For probe-free USB-bootloader flashing, take `_wchisp_variant`.

### 3a. Make flow (ch32fun)

```bash
cp -r $CH32V_FUN/examples/blink/* .          # V003
cp -r $CH32V_FUN/examples_v20x/blink/* .     # V203 — the V003 examples do NOT build for it
```

Create `funconfig.h` with the right family define. ch32fun's `Makefile`
includes `ch32fun/ch32fun.mk`; include it via `$(CH32V_FUN)/ch32fun/ch32fun.mk` (`/opt/ch32fun`). Never export `CH32FUN` itself.

See the `ch32fun-cpp-template` skill for adding C++ to a ch32fun project.

### 3b. CMake flow

```cmake
cmake_minimum_required(VERSION 3.20)
project(firmware C CXX ASM)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(HOST_TESTS "Build native unit tests instead of firmware" OFF)
if(HOST_TESTS)
    include(/opt/embedded/cmake/host-test.cmake)
    add_host_test_suite(logic_tests SOURCES test/host/test_placeholder.cpp INCLUDES src)
    return()
endif()

include(/opt/embedded/cmake/embedded-common.cmake)

add_executable(firmware
    src/main.cpp
    ${CH32FUN_DIR}/ch32fun.c
)
target_include_directories(firmware PRIVATE src ${CH32FUN_DIR})
target_link_options(firmware PRIVATE -T ${CMAKE_SOURCE_DIR}/linker.ld -nostartfiles)
embedded_stack_usage(firmware)
```

Configure through the toolchain file, which the `_cmake_variant` build command
already does:
`-DCMAKE_TOOLCHAIN_FILE=/opt/embedded/cmake/toolchains/riscv-none-elf.cmake -DRISCV_MARCH=... -DRISCV_MABI=...`

It refuses to configure without both, and rejects an rv32e/ilp32 mismatch.

> `embedded_hardening()` from the shared CMake helpers assumes newlib specs
> flags that ch32fun does not use. On WCH set the flags directly:
> `-fno-exceptions -fno-rtti -fno-threadsafe-statics -ffunction-sections
> -fdata-sections -Os -Wall -Wextra` and link with `-Wl,--gc-sections -nostdlib -lgcc`.

### 4. Linker script

Flash base differs by part — **`0x00000000` on the CH32V003**, `0x08000000` on
the V20x/V30x. Copy from the matching ch32fun example rather than adapting
another family's, then run `linker-script-audit`.

### 5. Verify — report the actual output

```bash
mcu --list
mcu build
mcu size
riscv-none-elf-readelf -A build/firmware.elf | grep Tag_RISCV_arch
```

The `readelf` line proves the ISA matches the part. On a V003 also confirm
`.init_array` is present if you use C++ globals.

### 6. Report next steps

- Whether a WCH-Link is visible (`wlink info`) or the `wchisp` USB-bootloader
  path should be used instead
- That SWIO on the CH32V003 is **PD1** — configuring it as a GPIO in your own
  firmware disables the debug interface. See `ch32v-flash-verify` for the
  recovery procedure, which is worth reading *before* it happens.
- On the V003, that 2 KB of SRAM means no heap, no `printf`, and a stack budget
  worth checking with `stack-usage-estimate` from the start

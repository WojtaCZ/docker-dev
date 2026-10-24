---
name: arm-project-layout
description: "The canonical directory tree and CMake rules for every Cortex-M firmware project (STM32, RP2040, MSPM0): per-project toolchain wrapper, startup/ vs src/, lib/ submodules only, embedded_hardening(), host tests in src/logic. Use when creating, scaffolding or restructuring an ARM firmware project or reviewing its CMakeLists.txt."
---

# ARM project layout

`/stm32-new-project` and `/scaffold-mcu-project arm <part>` create this tree.

Every firmware project created in this image uses this tree. It is the house
style (derived from `WojtaCZ/f401-template`, with the deviations below baked
in). Follow it; do not invent a per-part variant.

```
<project>/
├── CMakeLists.txt              root; explicit source list, never file(GLOB)
├── .mcu-profile.json           chip, core, fpu, build/flash/debug commands
├── .gitignore                  build/  build-host/  .vscode/.profile.env
├── README.md                   board, pinout, and why this flash tool
├── .vscode/{tasks,launch}.json
├── cmake/
│   ├── toolchain-arm-none-eabi.cmake   pins ARM_CORE/ARM_FPU/ARM_FLOAT_ABI
│   └── linker.cmake                    applies -T, sets LINK_DEPENDS
├── linker/<PART>_FLASH.ld      a directory: TrustZone parts need two scripts
├── svd/<PART>.svd
├── startup/                    vendor asm + system_stm32<fam>xx.c
├── inc/                        headers
├── src/                        main.cpp and project sources
│   └── logic/                  hardware-independent; compiled both ways
├── lib/                        third-party only, as submodules
├── test/host/                  native unit tests, -DHOST_TESTS=ON
└── build/                      generated, ignored
```

What makes it work — each of these is load-bearing:

- **`cmake/toolchain-arm-none-eabi.cmake` is a per-project wrapper, not a copy
  of the shared file.** It `set()`s `ARM_CORE`/`ARM_FPU`/`ARM_FLOAT_ABI` for
  this board, `include()`s `/opt/embedded/cmake/toolchains/arm-none-eabi.cmake`,
  then appends those three to `CMAKE_TRY_COMPILE_PLATFORM_VARIABLES`. Without
  that last step CMake's "Detecting CXX compiler ABI info" sub-configure does
  not inherit the cache vars and trips the shared file's `ARM_CORE` guard. The
  profile's `build` command points at the wrapper, not the shared file.
- **`startup/` is vendor code, `src/` is yours.** Copy `startup_<part>.s` and
  `system_stm32<fam>xx.c` out of `$STM32_CMSIS_DIR` into `startup/`; never edit
  them in place.
- **`lib/` is only for what this image does not ship** — tinyusb, etl,
  littlefs, nanopb — added as git submodules, not copied trees. **Never vendor
  CMSIS into `lib/`**: use `$CMSIS_DIR/CMSIS/Core/Include` and
  `$STM32_CMSIS_DIR/<fam>/Include`. The f401 template checks in `lib/CMSIS`;
  inside this container that is a stale duplicate of the baked headers.
- **No hand-rolled flag block.** Warnings, hardening and artefacts come from
  `embedded_hardening()` / `embedded_artifacts()` /
  `embedded_stack_usage()` in `/opt/embedded/cmake/embedded-common.cmake`. The
  f401 template's `VALIDATION_OPTS` / `OPTIMIZATIONS` / `LIBS` lists are
  superseded — do not carry them forward.
- **Hardware-independent logic goes in `src/logic/`**, which is the layout
  `/opt/embedded/cmake/host-test.cmake` expects: those files are listed as
  `UNDER_TEST` and compiled both ways — cross-compiled into the firmware and
  natively into the host-test binary. Host tests configure in their own build
  dir with **no** toolchain file (`cmake -S . -B build-host -DHOST_TESTS=ON`);
  `host-test.cmake` hard-errors if included while cross-compiling.
- **Target name is `${PROJECT_NAME}` — do not append `.elf`.**
  `embedded_artifacts()` sets a `.elf` `SUFFIX` on the target; giving it a
  target already named `<name>.elf` produces `<name>.elf.elf` and `mcu size`
  can't find the result. The output file is `<name>.elf`, and that is what
  `.mcu-profile.json`'s `ELF` must match.
- **`build/` is generated.** The upstream f401 template commits it; do not.

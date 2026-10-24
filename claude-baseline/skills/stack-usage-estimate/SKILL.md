---
name: stack-usage-estimate
description: "Estimate worst-case stack depth from -fstack-usage .su files and the call graph. Use when a stack overflow is suspected, when sizing the stack in the linker script, or on a part with 1-2 KB of RAM."
---

# Stack Usage Estimation

Estimate worst-case stack depth using compiler-generated `.su` files and manual call-graph analysis.

> Binutils calls below use `${CROSS_PREFIX}`. It is per-project, not a container
> variable: from the project directory run `CROSS_PREFIX="$(mcu --cross-prefix)"`
> (`arm-none-eabi-`, `riscv-none-elf-` or `tc32-elf-`, taken from `.mcu-profile.json`).

## Step 1: Enable stack usage output

In CMakeLists.txt, add:
```cmake
target_compile_options(<target> PRIVATE -fstack-usage)
```

Rebuild: `cmake --build build`. Each `*.su` file appears alongside the object file in `build/`.

## Step 2: Collect all .su entries

```bash
find build -name "*.su" | xargs cat | sort -t: -k2 -n -r | head -40
```

Format: `source_file:line:col:function_name   N   static/dynamic/bounded`

- `static` — known at compile time (safe).
- `dynamic` — depends on runtime value (flag for review).
- `bounded` — dynamic but compiler proved it is bounded (acceptable with verification).

## Step 3: Identify the call graph manually

For each execution context (main loop, each ISR, each RTOS task):

```bash
${CROSS_PREFIX}objdump -d build/firmware.elf | grep -A2 "bl\b\|blx\b\|bl\." | head -60
```

Or use `cflow` if available:
```bash
cflow --main=<entry_function> src/*.cpp 2>/dev/null | head -40
```

Manually trace the deepest call chain from the entry point.

## Step 4: Sum the chain

For the deepest call chain, sum `.su` values:
```
main                   →   64 bytes
  sensor_read          →   48 bytes
    spi_transmit       →   32 bytes
      spi_wait_ready   →   16 bytes
TOTAL                  =  160 bytes
```

Add ISR overhead (Cortex-M: 8 registers × 4 bytes = 32 bytes pushed by hardware on exception entry).

## Step 5: Compare against linker script allocation

```bash
${CROSS_PREFIX}nm build/firmware.elf | grep -E "_estack|_Min_Stack_Size|_stack_size"
${CROSS_PREFIX}size build/firmware.elf
```

Check that `(worst-case stack depth) + (RTOS overhead if any) + (safety margin ~256 bytes)` fits within the allocated stack region.

## Red flags

- Any `dynamic` entry in a frequently-called function or ISR — trace what drives the allocation.
- Recursive functions (almost always wrong on bare metal).
- `sprintf` / `printf` family — pulls in ~2 KB of stack in the deepest path.
- `__aeabi_dcmp` / `__aeabi_dadd` (double-precision soft-float) — 200–400 bytes deep.

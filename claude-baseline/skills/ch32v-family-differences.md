# CH32V / CH32X Family Differences

The V003 is not representative of the range. Code and advice that works on it
frequently does not port to a V203 or X033, and vice versa. Check this table
before assuming.

## The parts

| Part | Core | ISA | ABI | Flash | SRAM | Interrupt ctrl | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CH32V003 | QingKe V2A | `rv32ec_zicsr` | `ilp32e` | 16 KB | 2 KB | PFIC, 2-level nesting | **16 registers, no hardware multiply** |
| CH32V103 | QingKe V3A | `rv32imac_zicsr` | `ilp32` | 32–64 KB | 10–20 KB | PFIC | |
| CH32V203 | QingKe V4B | `rv32imac_zicsr` | `ilp32` | 32–64 KB | 10–20 KB | PFIC, HPE | USB FS device+host, CAN |
| CH32V303 | QingKe V4F | `rv32imafc_zicsr` | `ilp32f` | 62–128 KB | 32 KB | PFIC, HPE | **Single-precision FPU** |
| CH32X033 | QingKe V4C | `rv32imac_zicsr` | `ilp32` | 62 KB | 20 KB | PFIC | USB FS, no external crystal needed |

## What actually breaks when porting

### 1. ISA and ABI are not interchangeable

`ilp32e` (RV32E, 16 registers) and `ilp32` (RV32I, 32 registers) are **not**
link-compatible. A static library or object built for one will not link against
the other, and if you force it, arguments are passed in registers that do not
exist.

RV32EC also has **no `M` extension** — no hardware multiply or divide. Every
`a * b` becomes a `__mulsi3` libgcc call. On a 16 KB part that is both a code
size and a performance issue; check the map file if flash is tight.

```bash
riscv-none-elf-readelf -A build/firmware.elf | grep Tag_RISCV_arch
```

### 2. Memory budget

2 KB of SRAM on the V003 versus 20–32 KB elsewhere is a different kind of
programming, not the same programming with smaller numbers:

- No heap, no `new`, no `std::string`, no `std::function`.
- No `printf` (4–8 KB of flash on its own). Use a UART ring buffer.
- Stack typically 256–512 bytes. One 256-byte local buffer is a crash.
- `constexpr` and templates are free at run time — lean on them.

Run `stack-usage-estimate` on V003 projects as a matter of course, and set a
real `sizeBudget` in `.mcu-profile.json` so `mcu size` fails the build before
the linker silently overflows.

### 3. Peripheral availability

USB exists on V203/V303/X033 and **not** on the V003. CAN is V203/V303 only.
The V003 has no crystal oscillator support worth relying on — its 24 MHz
internal RC has a few percent tolerance, which is too loose for high UART
baud rates.

### 4. Interrupt controller

All use WCH's **PFIC**, not the standard RISC-V PLIC — so generic RISC-V
material about PLIC does not apply. V4 cores add HPE (hardware prologue/epilogue)
which pushes and pops the context automatically; V2A does not, so a V003 ISR
needs `__attribute__((interrupt))` and the compiler-generated prologue.

```c
// V003 (V2A): compiler must generate the save/restore
__attribute__((interrupt("WCH-Interrupt-fast")))
void TIM1_UP_IRQHandler(void) { ... }
```

Cross-check NVIC/PFIC priorities with the `interrupt-priority-audit` skill.

### 5. Clock trees differ

The V003's RCC is a cut-down version. Do not copy a V203 clock init to a V003 —
the register layout and the available PLL sources are not the same. Derive the
tree with `clock-tree-derive` after any change.

## Choosing the profile

`.mcu-profile.json` carries `march` and `mabi`, and `_chips` in the shipped
`profile.json` has an entry per part. For a CH32V203:

```jsonc
{
  "chip": "CH32V203C8T6",
  "core": "rv32imac",
  "march": "rv32imac_zicsr",
  "mabi": "ilp32",
  "sizeBudget": { "flash": 65536, "ram": 20480 }
}
```

## ch32fun coverage

`/opt/ch32fun` (formerly ch32v003fun) now supports the whole range, not just the
V003. The `funconfig.h` mechanism selects the target:

```c
#define CH32V20x 1        // or CH32V003, CH32V10x, CH32V30x, CH32X03x
#include "funconfig.h"
```

Examples live under `$CH32V_FUN/examples` (V003) and `$CH32V_FUN/examples_v20x`,
`examples_v30x`, `examples_x035` / `examples_x00x`. Copy from the one matching your part — the
V003 examples will not build unchanged for a V203.

## Flashing differs too

| Part | wlink (WCH-Link) | wchisp (USB bootloader) |
| --- | --- | --- |
| CH32V003 | ✅ SWIO on PD1 | ✅ BOOT0 = PD7 |
| CH32V103/203/303 | ✅ SWIO | ✅ native USB |
| CH32X033 | ✅ SWIO | ✅ native USB |

On parts with native USB, `wchisp` needs no USB-serial adapter at all — plug the
board straight in with BOOT0 held. That is usually the fastest bring-up path,
and the reliable recovery route when firmware has disabled SWIO. See
`ch32v-flash-verify`.

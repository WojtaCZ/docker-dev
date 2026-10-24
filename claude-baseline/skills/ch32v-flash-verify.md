# CH32V Flash and Connection Troubleshooting

The WCH equivalent of the generic `probe-troubleshoot` skill. CH32V parts use
**SWIO**, a single-wire debug interface that is considerably touchier than SWD,
and the CH32V003 in particular has a habit of locking itself out.

## Step 1: Is the probe there at all?

```bash
lsusb | grep -i 1a86
# 1a86:8010  WCH-Link (RV mode)   <- what you want for CH32V
# 1a86:8012  WCH-Link (DAP mode)  <- ARM mode; needs a mode switch
# 1a86:8011  WCH-LinkE
wlink info
```

**Nothing at all** → `/dev/bus/usb` not passed through, or the probe was
plugged in after the container started. Restart the container.

**Seen by `lsusb` but `wlink` says permission denied** → host udev rules not
installed. `sudo /opt/embedded/install-host-udev-rules.sh` **on the host**, then
replug.

**Enumerates as `1a86:8012`** → the WCH-Link is in ARM/DAP mode and will not
talk to a RISC-V target. Switch it:

```bash
wlink mode-switch --rv
```

## Step 2: `wlink` sees the probe but not the chip

Work down this list; it is roughly ordered by how often each is the cause.

1. **Power.** The WCH-Link's 3V3 pin supplies only a little current. A board
   with an LDO, LEDs and peripherals may brown out during flashing. Power the
   board externally and connect only SWIO + GND.
2. **Ground.** SWIO is single-wire — it is unusable without a solid common
   ground. A missing or long ground return is the classic intermittent case.
3. **Wire length.** SWIO is unterminated and sensitive; keep it under ~10 cm.
   A breadboard jumper run will fail where a short lead works.
4. **SWIO pin repurposed by your own firmware.** On the CH32V003, SWIO is
   **PD1**, which is also a GPIO. Configure PD1 as an output in your code and
   you disable the debug interface at the moment it starts running — the
   classic "I flashed once and now it will not connect".
5. **The chip is asleep.** If the firmware enters standby quickly, the debug
   interface goes with it.
6. **`RESET` / `NRST` behaviour.** Try holding reset, or:
   ```bash
   wlink --chip CH32V003 --speed low reset
   ```

## Step 3: Recovering a locked-out chip

This is the one that saves boards. If the running firmware disables SWIO
(case 4 or 5 above), a normal connection attempt always loses the race. `wlink`
can hold the target in reset while it attaches:

```bash
# Erase while holding reset — wins the race against firmware that kills SWIO
wlink erase --method power-off
wlink erase --method pin-rst

# Slow the interface right down; marginal wiring often works at low speed
wlink --speed low erase chip
```

If SWIO is genuinely unrecoverable, use the **USB bootloader** instead — it is
in ROM and firmware cannot disable it:

```bash
# Hold BOOT0 high while applying power / plugging in USB
wchisp probe
wchisp flash build/firmware.bin
```

That path needs no probe at all, and is the reliable escape hatch. On the
CH32V003 BOOT0 is PD7.

## Step 4: Flashing succeeds but the firmware does not run

```bash
# Is the image the right shape and size?
mcu size
riscv-none-elf-objdump -h build/firmware.elf | head -20

# First instruction should be at the flash base (0x00000000 as seen by the core)
riscv-none-elf-objdump -d build/firmware.elf | head -20
```

Check:

- [ ] `-march` / `-mabi` match the part. **RV32EC (CH32V003) has 16 registers
      and no hardware multiply.** Code built as `rv32imac`/`ilp32` links and
      then executes illegal instructions. Verify:
      ```bash
      riscv-none-elf-readelf -A build/firmware.elf | grep Tag_RISCV_arch
      ```
- [ ] The vector table is at the start of flash and `KEEP`-ed.
- [ ] `.data` copy and `.bss` zero happen before `main()`.
- [ ] `.init_array` is walked, if you use C++ globals with constructors.
- [ ] The stack pointer is set to the top of RAM — 2 KB on the V003, so
      anything recursive or with a large local array overflows immediately.
- [ ] `mtvec` points at the trap handler, with the correct mode bits.

## Step 5: It runs but behaves oddly

- **2 KB SRAM.** No heap, no `printf`, no `std::string`. Run
  `stack-usage-estimate`; a single careless local buffer is the whole budget.
- **Internal RC oscillator.** The V003 defaults to a 24 MHz HSI with a few
  percent tolerance — too loose for tight UART timing. Use a lower baud rate or
  an external crystal.
- **No hardware multiply on RV32EC.** `a * b` becomes a libgcc call, which is
  slow and pulls in code. Check for `__mulsi3` in the map if flash is tight.

## Decoding a trap

Read `mcause`, `mepc`, `mtval`, then symbolise — the `hardfault-decode` skill
has the `mcause` table:

```bash
riscv-none-elf-addr2line -f -C -e build/firmware.elf <mepc>
```

| `mcause` | Most likely cause on CH32V |
| --- | --- |
| 2 (illegal instruction) | Built for the wrong `-march` — RV32IMAC code on an RV32EC core |
| 5 / 7 (load/store access fault) | Pointer past the end of 2 KB SRAM, or a peripheral whose clock is gated |
| 1 (instruction access fault) | Jumped through a corrupt function pointer, or past the end of flash |

## Quick diagnostic

```bash
echo "== probe ==";  lsusb | grep -i 1a86 || echo "(no WCH device on USB)"
wlink info 2>&1 || true
echo "== target =="; wlink status 2>&1 || true
echo "== groups ==";  id
echo "== profile =="; mcu --list 2>/dev/null || echo "(no .mcu-profile.json here)"
echo "== bootloader fallback =="; wchisp probe 2>&1 || echo "(no device in ISP mode)"
```

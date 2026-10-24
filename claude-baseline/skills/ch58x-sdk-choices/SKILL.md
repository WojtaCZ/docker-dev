---
name: ch58x-sdk-choices
description: Choosing the software stack for a WCH CH58x (CH582F/CH583) project - ch32fun (open, no vendor code) vs WCH's official EVT SDK (needed for the BLE stack), the toolchain flags, memory map and build recipe. Use when starting or scaffolding any CH582F/CH583 firmware.
---

# CH582F software stack

Chip: **QingKe V4A, RV32IMAC** (`-march=rv32imac -mabi=ilp32`), **448 KB flash**, **32 KB RAM**
(CH582/583), USB 2.0 FS device+host, BLE 5.3, 2 SPI, 4 UART, I2C, 12-bit ADC, touch.
`F` = the QFN28 package; the `F`/`M`/`D` suffix changes available pins, not the core.
The xPack GCC in this image builds it; **no MounRiver toolchain needed** (that is only
for CH584/585, which use a WCH-private `mcpy` instruction).

## Option A - ch32fun (default; no BLE stack)

Open, header + startup + linker script generated from `TARGET_MCU`. Examples for this
family: `$CH32V_FUN/examples_ch5xx/` (`blink`, `uartdemo`, `adc_*`, `lowpower`, `RTC_irq`,
`systick_irq`, `boot_button`, `debugprintfdemo`, `spi_tx`, `ws2812bdemo`, `ble_beacon`, `iSLER`).
`ble_beacon` and `iSLER` drive the radio through ch32fun's open register-level code
(advertising / raw packets), not WCH's BLE stack.

```make
all : build
TARGET:=firmware
TARGET_MCU:=CH582F
include $(CH32V_FUN)/ch32fun/ch32fun.mk
flash : ; wchisp flash $(TARGET).bin
clean : cv_clean
```

Copy `funconfig.h` from an example. **Do not export `CH32FUN`**: ch32fun's own makefile
reads it as the path of its `ch32fun/` subdirectory. This image exposes the repo root as
`$CH32FUN_ROOT` (alias `$CH32V_FUN`) instead. The flash rule must use `wchisp`;
the stock `cv_flash` target uses `minichlink` (WCH-Link), which is not USB ISP.

Outputs: `firmware.elf/.bin/.hex/.lst/.map`. The link step prints flash/RAM usage.

## Option B - official EVT SDK (needed for the full BLE stack)

`ch58x-sdk` clones `openwch/ch583` (Apache-2.0) into `/workspace/.ch58x-sdk`. It gives
`EVT/EXAM/SRC` (StdPeriphDriver, RVMSIS, startup, `Ld/Link.ld`) and `EVT/EXAM/BLE/*`
(peripheral/central/broadcaster examples), with the BLE stack as a **prebuilt binary
library** - closed source, which is why it is not baked into the image.

WCH ships only MounRiver `.cproject` files, no Makefile. Build flags: `-march=rv32imac_zicsr
-mabi=ilp32`, the example's `Link.ld`, `startup_CH583.S`, the StdPeriphDriver sources, and the
BLE library linked with `-Wl,--start-group`. The community converter
`cjacker/ch5xx_riscv_ble_evt_makefile_gcc_project_template` generates a Makefile from the EVT zip.
**Not verified in this image: link a BLE example before relying on it.**

Also useful in that repo: `Datasheet/WCH BLE Software Development Reference Manual.pdf`, and OTA/IAP
examples under `EVT/EXAM/BLE/*OTA*` and `*IAP*`.

## Debugging

USB ISP cannot debug. For breakpoints use a WCH-Link(E) on the 2-wire SWD pins after
`wchisp config enable-debug`; `wlink` flashes and debugs. ch32fun's GDB support is best
tested on the V003 and only partly on other chips. Otherwise debug with printf (USB or UART).

## Not applicable here

`flashTool: wlink`/`openocd`, V003 SWIO recovery, `rv32ec`: those are the CH32V paths.

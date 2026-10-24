---
name: ch58x-usb-isp
description: Flash, erase, configure and recover a WCH CH58x (CH582F/CH583/...) over its USB port with wchisp - entering the boot ROM, usbipd/WSL attach, option bytes, SWD enable, and why the device "disappears". Use whenever flashing a CH582F, or `wchisp` finds no device.
---

# CH58x (CH582F) over USB ISP

The CH58x has a factory boot ROM that enumerates as USB **`4348:55e0`** (WinChipHead)
and speaks the WCH ISP protocol. `wchisp` (in this image) drives it. **No probe is
needed.** The chip is only visible on USB while that boot ROM runs.

## Enter the boot ROM

1. Unplug USB.
2. Hold **BOOT** (on CH58x the default download pin is **PB22**, low = enter ISP; it
   can be moved to PB11 via the `DOWNLOAD_CFG` config bit).
3. Plug USB in, release BOOT after about a second.
4. `lsusb | grep 4348:55e0` must show it. Then `wchisp info`.

If the board has a RESET button instead: hold BOOT, tap RESET, release BOOT.
The boot ROM waits only a few seconds for a host; no host contact = it boots the app.

Firmware that re-purposes PB22 as GPIO, or a battery that keeps the chip powered, blocks
step 3 (no power-on reset). Disconnect the battery, or jump to the ROM from firmware:
`jump_isprom()` in ch32fun's `examples_ch5xx/boot_button`.

## Commands

```bash
wchisp probe                   # list ISP devices; use `-d <index>` if several
wchisp -r 10 info              # keep retrying for 10 s - handy right after plugging in
wchisp info                    # chip, UID, bootloader version, config registers
wchisp flash firmware.bin      # also accepts .hex / .elf; verifies, then resets
wchisp erase
wchisp reset
wchisp config info             # option bytes, decoded
wchisp config enable-debug     # turn on the 2-wire SWD interface (see below)
```

`mcu flash` / `mcu erase` / `mcu reset` do the same through `.mcu-profile.json`
(copy `/opt/embedded/profiles/ch582f.json`).

## WSL2 / usbipd (the part that bites)

The chip **re-enumerates**: it is a different USB device (`4348:55e0`) in boot mode
than as your application, and after flashing it resets and vanishes. usbipd treats
each appearance as needing attach.

```powershell
# once, admin:   share by VID:PID so it survives the re-enumeration
usbipd bind --hardware-id 4348:55e0
# every WSL boot, then every time the ROM reappears:
usbipd attach --wsl --auto-attach --hardware-id 4348:55e0
```

`--auto-attach` keeps retrying, so unplug / BOOT+replug / flash works without
retyping. `dev-up.sh` mounts `/dev/bus/usb` live, so a device attached after the
container started is visible to `wchisp` with no restart. Check with `lsusb`.

## Option bytes and SWD

- A fresh CH582F can have the 2-wire debug interface **disabled**; `wchisp config enable-debug`
  writes WCH's known-good config (`CFG_DEBUG_EN`). Needed before a WCH-Link can attach.
- `CFG_ROM_READ`/code protection: a protected chip cannot be read back; flash still works.
- Do not hand-edit the config words (`wchisp config set`) without reading `wchisp config info`
  first - `CFG_RESET_EN`, `CFG_BOOT_EN` and the download-pin bit can make the ROM unreachable.

## Printf / logs over the same USB port

ch32fun can run a USB debug-print channel on the chip's USB (`FUNCONF_USE_USBPRINTF`);
call `USBFSReset()` before `jump_isprom()` when using it. Otherwise use a UART pin
with a USB-serial adapter (`picocom`).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `wchisp: no device found` | Not in ROM mode (retry the entry sequence), not attached to WSL (usbipd), or container started without `/dev/bus/usb` (restart `dev-up.sh` after `usbipd attach`) |
| permission denied | host udev: `sudo /opt/embedded/install-host-udev-rules.sh`, replug. In WSL as root it is not needed |
| flashes fine, app does nothing | wrong `TARGET_MCU`/package (CH582F vs CH582M change pins/defines), or clock/`SystemInit()` missing |
| bootloader unreachable after your firmware | firmware changed PB22 or disabled the boot enable; hold BOOT through power-up, or erase with a WCH-Link |

---
name: ppk2-power-profiling
description: "Measure target current/power with the Nordic Power Profiler Kit II (PPK2, USB 1915:c00a) via the `ppk2` CLI: sleep/active current in uA, battery-life estimates, charge per event, BLE/radio burst profiling, powering a DUT from the PPK2 (source meter) or in series with your own supply (ampere meter), digital-channel timing. Use for 'how much current does it draw', 'low-power regression', 'PPK2 not found', ttyACM 1915."
---

# PPK2 power profiling

The PPK2 is a CDC-ACM serial device (`1915:c00a`, `/dev/ttyACM*`, product string `PPK2`). It exposes TWO ttyACM ports; only the lower-numbered interface (`...-if01` in `/dev/serial/by-id`) speaks the protocol, and `ppk2` picks it for you. The kernel's `cdc_acm` is the only driver; there is nothing to install in the container. Everything goes through `ppk2` (image-owned CLI over `ppk2-api`, venv in `/opt/ppk2`). All commands print JSON.

## 0. Is it visible? (do this first, every time)

```bash
ppk2 list                 # exit 1 + empty list when absent
lsusb | grep 1915         # expect 1915:c00a
```

Not listed:
- Cable must be in the **DATA/POWER** USB port (not the power-only one); use a data cable; side power switch **on**.
- Host: `journalctl -k -n 20` must show a `cdc_acm ... ttyACM` line. Nothing there = it never enumerated (cable/switch), not a driver problem.
- Present on the host but not in the container: `dev-up.sh` / the udev attach rule mirrors `/dev/ttyACM*` into a running container; re-run `dev-up.sh` or `dev-attach attach /dev/ttyACMn`.
- `Permission denied` on the port: the host needs `sudo scripts/install-host-udev-rules.sh` once (installs `60-nordic-ppk2.rules`, which also tells ModemManager to leave the port alone; ModemManager probing it garbles the protocol).
- `cannot open ... busy`: only ONE process may own the port. Close nRF Connect Power Profiler, any earlier `ppk2` run, or `picocom` on it.

## 1. Pick the mode (this decides what is energised)

| Mode | Wiring | PPK2 does |
|---|---|---|
| `ampere` | your supply -> PPK2 `VIN` -> PPK2 `VOUT` -> target | measures only; never powers the target |
| `source` | PPK2 `VOUT` -> target VDD (target unpowered otherwise) | **supplies** 0.8-5.0 V and measures |

**Safety rule: in source mode, ask the user for the target's VDD (and confirm it is within the part's absolute maximum) BEFORE passing `--mv` / `--power-dut` / `dut on`.** Never guess a voltage, never raise it to "make it boot". VOUT is only driven when `--power-dut` or `ppk2 dut on` is given; VOUT is dead whenever no process holds the port: it drops the moment `ppk2` exits (verified on hardware), so a multimeter reading after the command returns shows 0 V. Do not connect another supply to a target that the PPK2 is powering.

## 2. Measure

```bash
# external supply, 10 s, 1 kHz CSV, find radio bursts above 1 mA
ppk2 measure --mode ampere --seconds 10 --csv /tmp/run.csv --burst-ua 1000

# PPK2 powers the target at the user-confirmed VDD
ppk2 measure --mode source --mv 3300 --power-dut --seconds 10

ppk2 dut on --mv 3300 --hold 120 &   # BLOCKS holding the port, so background it; powers the target (e.g. to flash it or meter VOUT)
                                     # power ends when it exits (--hold timeout, or kill it); no measuring while held (one port owner)
```

Output keys: `avg_uA, min_uA, max_uA, p50_uA, p99_uA, charge_uC` (avg x duration), `energy_uJ` (charge x VDD), `duration_s`, `samples` (100 kS/s, so `samples == 100000 x s`), `digital_edges` (`D0..D7`: `[time_s, level]`, the PPK2 logic inputs, handy to timestamp a GPIO "radio on"/"sleep" marker from firmware), and with `--burst-ua` a `bursts` list (`start_s, dur_ms, charge_uC, peak_uA`). A `warning` about a short capture means USB reads fell behind; shorten `--seconds` or close other USB-heavy work.

CSV is decimated (`--decimate 100` -> 1 kHz, both mean and max per row); keep the default for long runs, `--decimate 1` only for sub-second captures (100k rows/s).

## 3. Method that gives trustworthy numbers

1. Measure the **idle/sleep floor** first (target in deepest sleep, debugger disconnected: SWD probes and USB-UART bridges leak/feed current). Typical floor: single-digit uA.
2. Capture >= several full duty cycles. A single `avg_uA` over 1 s says nothing about a 5 s advertising interval; size `--seconds` to >= 3 periods.
3. Battery life: `hours = capacity_mAh / (avg_uA / 1000)`, derate 20-30% (self-discharge, temperature, cut-off voltage). Quote the assumptions.
4. Report `avg`, `p99`/`max`, and burst `charge_uC` separately. Compare against a stored baseline JSON when checking for regressions; keep results under the project, not the repo root.
5. The first ~0.3 s after `--power-dut` is boot; `--settle` skips it. The auto-range switching of the PPK2 causes a few-sample glitch at range changes; judge by `p50`/`avg`, not single `max_uA` samples.
6. Accuracy: below ~1 uA the PPK2 reading is dominated by offset; treat sub-uA differences as noise.

## 4. Typical combined workflow

Flash with the usual probe (`mcu flash` / `openocd` ...) -> `ppk2 dut on --mv <VDD>` if PPK2-powered -> have firmware toggle a GPIO wired to PPK2 `D0` around the work of interest -> `ppk2 measure ... --burst-ua <threshold>` -> correlate `digital_edges` with `bursts`.

Without hardware, `PPK2_SIMULATE=1 ppk2 measure ...` emits synthetic data (2 uA floor, 10 mA/1 ms burst every 100 ms) to test your analysis scripts; never present simulated numbers as measurements.

#!/opt/ppk2/bin/python
"""ppk2: command-line front end for the Nordic Power Profiler Kit II.

Wraps the ppk2-api serial protocol (100 kS/s, 8 digital channels). Every command
prints machine-readable JSON on stdout; diagnostics go to stderr.

  ppk2 list                                   find attached PPK2s
  ppk2 info   [--port P]                      calibration / hardware metadata
  ppk2 measure --mode ampere  [--seconds S] [--mv N] [--csv F]
  ppk2 measure --mode source  --mv N --power-dut [--seconds S] [--csv F]
  ppk2 dut on --mv N [--hold S]               power target; BLOCKS holding the port
                                              (VOUT drops when the port closes)

SOURCE mode: the PPK2 SUPPLIES the target at --mv (800-5000) and measures it.
It only drives VOUT when --power-dut (or `dut on`) is given, and switches it off
again on exit. (The PPK2 cuts VOUT whenever the port closes, so --keep-power
cannot persist after exit.) Never set --mv above the target's VDD rating.
AMPERE mode: the PPK2 sits in series with YOUR supply; it never drives the target.

PPK2_SIMULATE=1 replaces the hardware with synthetic data (tests, no device).
"""
import argparse
import json
import math
import os
import sys
import time

SAMPLE_RATE = 100_000  # Hz, fixed by the PPK2 firmware
VID, PID = 0x1915, 0xC00A


def die(msg, code=2):
    print(json.dumps({"error": msg}))
    print(f"ppk2: {msg}", file=sys.stderr)
    sys.exit(code)


class SimPPK2:
    """Synthetic stand-in: 2 uA sleep floor with a 10 mA burst every 100 ms."""

    def __init__(self, port, **kw):
        self.t0 = None
        self.n = 0
        self.current_vdd = None
        self.dut = "OFF"

    @staticmethod
    def list_devices():
        return ["/dev/ppk2-simulated"]

    def get_modifiers(self):
        return {"simulated": True}

    def use_ampere_meter(self): pass
    def use_source_meter(self): pass
    def set_source_voltage(self, mv): self.current_vdd = mv
    def toggle_DUT_power(self, s): self.dut = s
    def start_measuring(self): self.t0 = time.monotonic(); self.n = 0
    def stop_measuring(self): pass

    def get_data(self):
        want = int((time.monotonic() - self.t0) * SAMPLE_RATE) - self.n
        return b"x" * max(want, 0)

    def get_samples(self, buf):
        k = len(buf)
        out, bits = [], []
        for i in range(self.n, self.n + k):
            in_burst = (i % 10_000) < 100
            out.append(10_000.0 if in_burst else 2.0)
            bits.append(1 if in_burst else 0)
        self.n += k
        return out, bits

    def digital_channels(self, bits):
        return [[(b >> c) & 1 for b in bits] for c in range(8)]

    ser = None


def open_device(port):
    if os.environ.get("PPK2_SIMULATE") == "1":
        return SimPPK2("sim"), "/dev/ppk2-simulated"
    try:
        from ppk2_api.ppk2_api import PPK2_API
    except ImportError:
        die("ppk2_api not importable (image should ship it in /opt/ppk2)")
    if not port:
        devs = find_ports()
        if not devs:
            die("no PPK2 found: check cable is in the DATA/POWER port, side "
                "switch is on, and `lsusb | grep 1915` shows 1915:c00a")
        if len(devs) > 1:
            die(f"several PPK2s attached {devs}; choose one with --port")
        port = devs[0]
    try:
        dev = PPK2_API(port, timeout=1)
    except Exception as e:  # serial.SerialException: busy / permission
        die(f"cannot open {port}: {e}. Another process (nRF Connect, a "
            "previous ppk2 run) may hold it, or the udev rule is not installed")
    dev.get_modifiers()  # loads calibration: must precede any measurement
    return dev, port


def ppk2_ports():
    """One entry per physical PPK2. The PPK2 exposes TWO CDC ports (interfaces 1 and
    3); only the lower one speaks the measurement protocol (verified on hardware:
    the other answers nothing to GET_META_DATA)."""
    from serial.tools import list_ports
    best = {}
    for p in sorted(list_ports.comports(), key=lambda p: p.location or p.device):
        if p.vid == VID and p.pid == PID:
            best.setdefault(p.serial_number or p.device, p)
    return list(best.values())


def find_ports():
    return [p.device for p in ppk2_ports()]


def cmd_list(a):
    if os.environ.get("PPK2_SIMULATE") == "1":
        print(json.dumps({"devices": ["/dev/ppk2-simulated"], "simulated": True}))
        return
    devs = [{"port": p.device, "serial": p.serial_number, "product": p.product}
            for p in ppk2_ports()]
    print(json.dumps({"devices": devs}))
    if not devs:
        sys.exit(1)


def cmd_info(a):
    dev, port = open_device(a.port)
    m = dev.get_modifiers()
    print(json.dumps({"port": port, "calibrated": (m or {}).get("Calibrated") if isinstance(m, dict) else None,
                      "hw": getattr(dev, "modifiers", {}).get("HW")}))


def cmd_dut(a):
    """`dut on` HOLDS the serial port open: the PPK2 drops VOUT as soon as the
    port closes (verified on hardware), so this blocks until Ctrl-C/SIGTERM or
    --hold seconds, then powers the target off. Run it in the background."""
    import signal
    dev, port = open_device(a.port)
    dev.use_source_meter()
    if a.state == "off":
        dev.toggle_DUT_power("OFF")
        print(json.dumps({"port": port, "dut_power": "OFF"}))
        return
    if a.mv is None:
        die("`dut on` requires --mv (the target's supply voltage in mV)")
    check_mv(a.mv)
    dev.set_source_voltage(a.mv)
    dev.toggle_DUT_power("ON")
    print(json.dumps({"port": port, "dut_power": "ON", "mv": a.mv,
                      "note": "holding port; VOUT stays on until this process exits"}), flush=True)
    stop = []
    signal.signal(signal.SIGTERM, lambda *_: stop.append(1))
    signal.signal(signal.SIGINT, lambda *_: stop.append(1))
    end = time.monotonic() + a.hold if a.hold else None
    while not stop and (end is None or time.monotonic() < end):
        time.sleep(0.2)
    dev.toggle_DUT_power("OFF")


def check_mv(mv):
    if not 800 <= mv <= 5000:
        die("--mv must be within 800..5000 (PPK2 regulator range)")


def cmd_measure(a):
    if a.mode == "source":
        if a.mv is None:
            die("source mode requires --mv (the target's VDD in mV)")
        check_mv(a.mv)
    mv = a.mv if a.mv is not None else 3300  # ampere mode: only used for calibration maths
    dev, port = open_device(a.port)
    if a.mode == "source":
        dev.use_source_meter()
    else:
        dev.use_ampere_meter()
    dev.set_source_voltage(mv)
    if a.mode == "source" and a.power_dut:
        dev.toggle_DUT_power("ON")
        time.sleep(a.settle)
    elif a.mode == "source":
        print("ppk2: note: --power-dut not given, VOUT is NOT driven (PPK2 cuts it whenever no process holds the port)",
              file=sys.stderr)

    total = int(a.seconds * SAMPLE_RATE)
    decim = max(1, a.decimate)
    s_sum = s_cnt = 0
    peak = 0.0
    low = math.inf
    hist = []          # every sample, for percentiles (100k floats per second)
    csv_f = open(a.csv, "w") if a.csv else None
    acc = 0.0
    acc_n = 0
    if csv_f:
        csv_f.write(f"time_s,current_uA_mean_of_{decim},current_uA_max_of_{decim},digital_bits\n")
    csv_max = 0.0
    csv_bits = 0
    edges = [[] for _ in range(8)]
    prev_bits = None
    burst_state = False
    bursts = []        # (start_s, dur_s, charge_uC, peak_uA)
    cur = None
    seen = 0

    try:
        dev.start_measuring()
        t_end = time.monotonic() + a.seconds * 3 + 5  # wall-clock guard
        while seen < total and time.monotonic() < t_end:
            raw = dev.get_data()
            if not raw:
                time.sleep(0.002)
                continue
            samples, bits = dev.get_samples(raw)
            for i, v in enumerate(samples):
                if seen >= total:
                    break
                t = seen / SAMPLE_RATE
                seen += 1
                s_sum += v
                s_cnt += 1
                hist.append(v)
                peak = max(peak, v)
                low = min(low, v)
                b = bits[i] if i < len(bits) else 0
                if prev_bits is not None and b != prev_bits:
                    for c in range(8):
                        if (b ^ prev_bits) >> c & 1:
                            if len(edges[c]) < 200:
                                edges[c].append([round(t, 6), (b >> c) & 1])
                prev_bits = b
                if a.burst_ua is not None:
                    if v >= a.burst_ua:
                        if cur is None:
                            cur = [t, 0, 0.0, 0.0]
                        cur[1] += 1
                        cur[2] += v / SAMPLE_RATE
                        cur[3] = max(cur[3], v)
                    elif cur is not None:
                        bursts.append(cur)
                        cur = None
                if csv_f:
                    acc += v
                    acc_n += 1
                    csv_max = max(csv_max, v)
                    csv_bits |= b
                    if acc_n == decim:
                        csv_f.write(f"{t:.6f},{acc/acc_n:.3f},{csv_max:.3f},{csv_bits}\n")
                        acc = csv_max = 0.0
                        acc_n = csv_bits = 0
    finally:
        try:
            dev.stop_measuring()
        except Exception:
            pass
        if a.mode == "source" and a.power_dut:
            dev.toggle_DUT_power("OFF")
        if csv_f:
            csv_f.close()
    if cur is not None:
        bursts.append(cur)

    if not s_cnt:
        die("no samples received (device asleep, wrong mode, or port busy)")
    dur = s_cnt / SAMPLE_RATE
    avg = s_sum / s_cnt
    hist.sort()
    pct = lambda p: hist[min(len(hist) - 1, int(p / 100 * len(hist)))]
    out = {
        "port": port, "mode": a.mode, "vdd_mV": mv,
        "samples": s_cnt, "duration_s": round(dur, 6),
        "avg_uA": round(avg, 3), "min_uA": round(low, 3), "max_uA": round(peak, 3),
        "p50_uA": round(pct(50), 3), "p99_uA": round(pct(99), 3),
        "charge_uC": round(avg * dur, 3),
        "energy_uJ": round(avg * dur * mv / 1000, 3),
        "digital_edges": {f"D{c}": e for c, e in enumerate(edges) if e},
    }
    if s_cnt < total:
        out["warning"] = f"short capture: {s_cnt}/{total} samples (USB reads too slow?)"
    if a.burst_ua is not None:
        out["bursts"] = {
            "threshold_uA": a.burst_ua, "count": len(bursts),
            "list": [{"start_s": round(s, 6), "dur_ms": round(n / SAMPLE_RATE * 1000, 3),
                      "charge_uC": round(q, 4), "peak_uA": round(p, 1)}
                     for s, n, q, p in bursts[:200]],
        }
    if a.csv:
        out["csv"] = os.path.abspath(a.csv)
    print(json.dumps(out))


def main():
    p = argparse.ArgumentParser(prog="ppk2", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    i = sub.add_parser("info"); i.add_argument("--port"); i.set_defaults(fn=cmd_info)
    d = sub.add_parser("dut"); d.add_argument("state", choices=["on", "off"])
    d.add_argument("--mv", type=int); d.add_argument("--port")
    d.add_argument("--hold", type=float, help="seconds to keep power on (default: until killed)"); d.set_defaults(fn=cmd_dut)
    m = sub.add_parser("measure")
    m.add_argument("--mode", choices=["ampere", "source"], required=True)
    m.add_argument("--mv", type=int, help="target VDD in mV (required for source)")
    m.add_argument("--seconds", type=float, default=5.0)
    m.add_argument("--port")
    m.add_argument("--power-dut", action="store_true",
                   help="source mode: actually drive VOUT (off again at exit)")
    m.add_argument("--settle", type=float, default=0.3, help="seconds to wait after powering DUT")
    m.add_argument("--csv", help="write decimated samples to this file")
    m.add_argument("--decimate", type=int, default=100,
                   help="CSV: average N samples per row (100 = 1 kHz); default 100")
    m.add_argument("--burst-ua", type=float,
                   help="report bursts where current >= this threshold (uA)")
    m.set_defaults(fn=cmd_measure)
    a = p.parse_args()
    if getattr(a, "seconds", 1) <= 0 or getattr(a, "seconds", 1) > 600:
        die("--seconds must be in (0, 600]")
    a.fn(a)


if __name__ == "__main__":
    main()

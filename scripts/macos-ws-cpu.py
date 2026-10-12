#!/usr/bin/env python3
"""Read-only WindowServer CPU/flip measurement; no sudo or configuration changes.

Run once with visible windows, then with windows minimized, using distinct labels.
CPU uses cumulative process time, not ps's smoothed instantaneous %CPU.
"""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import time


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def snapshot(pid):
    raw = output("ps", "-p", pid, "-o", "time=")
    days, separator, clock = raw.partition("-")
    fields = (clock if separator else raw).split(":")
    cpu = 0.0
    for field in fields:
        cpu = cpu * 60 + float(field)
    if separator:
        cpu += int(days) * 86400
    observed = time.monotonic()
    counters = {}
    for line in output("sysctl", "-a").splitlines():
        key, _, value = line.partition(": ")
        if key.startswith(("debug.nvaccel_", "debug.nvrmfb_flip_")):
            try:
                counters[key] = int(value)
            except ValueError:
                pass
    return {"monotonic": observed, "cpu_seconds": cpu, "counters": counters}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=15)
    parser.add_argument("--label", default="visible")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300:
        parser.error("--seconds must be between 1 and 300")
    pid = output("pgrep", "-x", "WindowServer").splitlines()[0]
    first = snapshot(pid)
    time.sleep(args.seconds)
    last = snapshot(pid)
    if pid not in output("pgrep", "-x", "WindowServer").splitlines():
        raise RuntimeError("WindowServer restarted; discard this measurement")
    elapsed = last["monotonic"] - first["monotonic"]
    delta = {k: v - first["counters"][k] for k, v in last["counters"].items()
             if k in first["counters"]}
    result = {"label": args.label, "pid": int(pid), "seconds": elapsed,
              "cpu_percent_one_core": 100 * (last["cpu_seconds"] - first["cpu_seconds"]) / elapsed,
              "flip_per_second": delta.get("debug.nvrmfb_flip_n", 0) / elapsed,
              "counter_deltas": delta, "before": first, "after": last}
    directory = Path.home() / "efi-audit" / ("ws-cpu-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    directory.mkdir(parents=True)
    (directory / "measurement.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{args.label}: CPU {result['cpu_percent_one_core']:.1f}% of one core; "
          f"{result['flip_per_second']:.1f} flips/s over {elapsed:.2f}s")
    for key in ("debug.nvaccel_iop_ok_h0", "debug.nvaccel_iop_ok_h1",
                "debug.nvaccel_iop_fail", "debug.nvaccel_iop_async_drop"):
        print(f"{key}: +{delta.get(key, 'unavailable')}")
    print(directory / "measurement.json")


if __name__ == "__main__":
    main()

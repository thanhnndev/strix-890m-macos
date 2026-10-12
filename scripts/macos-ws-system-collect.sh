#!/bin/bash
# Read-only system-wide stacks and counters. Run as the login user, not `sudo bash`.
# sudo is used only for spindump/sample/vmmap. Nothing is installed or restarted.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HOME/efi-audit/ws-system-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
sudo -v
PID="$(pgrep -x WindowServer | head -1)"
echo "Collecting system/kernel stacks for 8 seconds; keep the current workload steady."
sw_vers > "$OUT/os.txt"
pmset -g batt > "$OUT/power.txt"
sysctl debug.amdcppc.freq debug.amdcppc.report > "$OUT/cpu-frequency-before.txt" 2>&1 || true
sysctl -a 2>/dev/null | awk '/^debug\.(nv|amdcppc)/' > "$OUT/counters-before.txt"
ps -axo pid,ppid,pcpu,time,comm > "$OUT/processes-before.txt"
sudo vmmap -summary "$PID" > "$OUT/ws-memory-before.txt" 2>&1 || true
sudo /usr/sbin/spindump -noTarget 8 10 -o "$OUT/system.spindump.txt" > "$OUT/spindump-status.txt" 2>&1 &
SPIN=$!
python3 "$HERE/scripts/macos-ws-cpu.py" --seconds 8 --label system-spindump > "$OUT/cpu-interval.txt" 2>&1 &
CPU=$!
wait "$SPIN" || echo "spindump failed; inspect spindump-status.txt" >&2
wait "$CPU" || echo "CPU interval failed; inspect cpu-interval.txt" >&2
echo "Collecting a higher-resolution WindowServer sample for 8 seconds."
sudo sample "$PID" 8 1 -file "$OUT/ws-sample.txt" > "$OUT/sample-status.txt" 2>&1 || true
sudo vmmap -summary "$PID" > "$OUT/ws-memory-after.txt" 2>&1 || true
sysctl debug.amdcppc.freq debug.amdcppc.report > "$OUT/cpu-frequency-after.txt" 2>&1 || true
sysctl -a 2>/dev/null | awk '/^debug\.(nv|amdcppc)/' > "$OUT/counters-after.txt"
ps -axo pid,ppid,pcpu,time,comm > "$OUT/processes-after.txt"
sudo chown -R "$(id -u):$(id -g)" "$OUT"
echo "DONE: $OUT"

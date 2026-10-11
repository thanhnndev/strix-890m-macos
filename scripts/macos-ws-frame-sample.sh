#!/bin/bash
# Samples WindowServer while tools/framepace.swift drives a known load (layer animation, then window move), so the
# sample and the flip counters describe the same frames. RUN ON macOS as your user; it asks for sudo only for `sample`.
# Output: ~/efi-audit/wsframe-<time>/ (framepace results + WindowServer samples). Nothing on the system is changed.
#   bash scripts/macos-ws-frame-sample.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HOME/efi-audit/wsframe-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
BIN="$OUT/framepace"
swiftc -O "$HERE/tools/framepace.swift" -o "$BIN" || { echo "swiftc failed"; exit 1; }
sudo -v || { echo "sudo is needed for sample WindowServer"; exit 1; }

"$BIN" idle 3 > "$OUT/idle.txt" 2>&1
for mode in anim move; do
  echo "== $mode: leave the mouse alone for ~10 s"
  "$BIN" "$mode" 8 > "$OUT/$mode.txt" 2>&1 &
  pid=$!
  sleep 3
  sudo sample WindowServer 4 1 -file "$OUT/ws-$mode.txt" >/dev/null 2>&1 || echo "sample failed" > "$OUT/ws-$mode.err"
  wait $pid
  grep -v '^nvrm:\|shader cache' "$OUT/$mode.txt"
done
sudo chown -R "$(id -u):$(id -g)" "$OUT"
echo "done: $OUT"

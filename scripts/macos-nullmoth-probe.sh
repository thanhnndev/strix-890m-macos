#!/bin/bash
# Read-only NullMoth/display probe. RUN ON macOS (no sudo needed). Output: ~/efi-audit/probe-<time>/
# Masks UUIDs, MACs, serials and SSIDs. Nothing is changed on the system.
#   bash macos-nullmoth-probe.sh            # snapshot
#   bash macos-nullmoth-probe.sh --window   # also 5 s WindowServer sample: DRAG A WINDOW while it runs
set -u
OUT="$HOME/efi-audit/probe-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

mask() {
  sed -E \
    -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<uuid>/g' \
    -e 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/<mac>/g' \
    -e '/IOPlatformSerialNumber|IOPlatformUUID|"serial-number"|"board-id"|Serial Number|"SSID|SSID_STR|"MLB"|"ROM"/ s/=.*/= <masked>/' \
    -e '/Serial Number|Hardware UUID|Provisioning UDID/ s/:.*/: <masked>/'
}
run() { # name command...
  local n="$1"; shift
  { echo "\$ $*"; "$@" 2>&1; } | mask > "$OUT/$n.txt"
}

run sw_vers          sw_vers
run uname            uname -a
run sysctl-nv        bash -c 'sysctl -a 2>/dev/null | grep -Ei "debug\.nv|nvaccel|nvrmfb|nvrm_|nvmtl"'
run kmutil           bash -c 'kmutil showloaded 2>/dev/null | grep -Ei "nullmoth|nvrm|nvaccel|nvidia|itl|Voodoo|Whatever|Lilu"'
run kextstat         bash -c 'kextstat 2>/dev/null | grep -Ei "nullmoth|nvrm|nvaccel|nvidia"'
run ioreg-nvrm       bash -c 'ioreg -l -w0 2>/dev/null | grep -Ei "nvrm|nvaccel|nvmtl|NullMoth" | head -300'
run ioreg-display    bash -c 'ioreg -l -w0 -r -c IOFramebuffer 2>/dev/null | grep -Ei "IOFBCurrentPixelClock|IOFBTimingRange|timing|refresh|IOFBDetailedTiming|IODisplayEDID|IOFBHiDPI|IOFBScalerInfo" | head -120'
run display          system_profiler SPDisplaysDataType
run nullmoth-dir     bash -c 'ls -la /Library/NullMoth 2>/dev/null; echo; echo "-- allow-list:"; cat /Library/NullMoth/nvmtl-allow.txt 2>/dev/null; echo; echo "-- driver-version:"; cat /Library/NullMoth/driver-version 2>/dev/null'
run display-trace    bash -c 'for f in trace.txt kernel.txt ws.txt; do echo "== $f"; tail -n 300 /Library/NullMoth/display-trace/$f 2>/dev/null; done'
run extensions       bash -c 'ls -la /Library/Extensions 2>/dev/null'
run override         bash -c 'ls -laR /Library/Displays/Contents/Resources/Overrides 2>/dev/null | head -60'
run log-nullmoth     log show --last 30m --style compact --predicate 'eventMessage CONTAINS[c] "NullMoth" OR eventMessage CONTAINS[c] "NVRM" OR eventMessage CONTAINS[c] "NVMTL" OR eventMessage CONTAINS[c] "NVAccel"'
run log-windowserver log show --last 10m --style compact --predicate 'process == "WindowServer" AND (messageType == error OR messageType == fault)'
run panics           bash -c 'ls -lat /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports 2>/dev/null | head -30'

if [ "${1:-}" = "--window" ]; then
  echo "Sampling WindowServer for 5 s. DRAG A WINDOW IN CIRCLES NOW."
  sleep 2
  sample WindowServer 5 -file "$OUT/ws-drag.txt" >/dev/null 2>&1 || echo "sample failed (try: sudo sample WindowServer 5 -file ...)" > "$OUT/ws-drag.err"
fi

echo "done: $OUT"
echo "Check the folder for anything you do not want shared, then copy it into ~/efi-audit/ (the Linux side reads it from the APFS volume)."

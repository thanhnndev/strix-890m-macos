#!/bin/bash
# Install the hardware-tested release candidate for NullMoth PR #139.
# Activation is at the next reboot/login; this script never restarts WindowServer.
# Usage: sudo bash scripts/macos-ws-upload-install.sh [--undo|--check]
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
BUNDLE=/Library/GPUBundles/NVMTLDriver.bundle
BIN=Contents/MacOS/NVMTLDriver
SOURCE=/Users/thanhnndev/efi-audit/ws-upload-candidate/NVMTLDriver
STATE=/Library/NullMoth/ws-upload-test
STAGE=/Library/GPUBundles/NVMTLDriver.ws-upload-stage.bundle
ORIGINAL=97dec4756bbf404dde6532e949237de9bafc8835e0640503b933001c753bb85b
CANDIDATE=5975192f1d5cc8ed8b6c2bcb53a1fe0ac55b301806e232cd0c49f0981b576d6a
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
swap() {
  /usr/bin/python3 - "$1" "$2" <<'PY'
import ctypes, os, sys
lib = ctypes.CDLL(None, use_errno=True)
rename = lib.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 2):
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
PY
}
CURRENT="$(sha "$BUNDLE/$BIN")"
MODE="${1:-install}"
if [[ "$MODE" == --check ]]; then
  [[ "$(sha "$SOURCE")" == "$CANDIDATE" ]] || { echo 'Candidate hash mismatch'; exit 1; }
  codesign --verify --strict "$SOURCE"
  echo "Current executable SHA256: $CURRENT"
  echo "Candidate executable SHA256: $CANDIDATE"
  echo 'PR #139 release candidate verified; installation requires sudo.'
  exit 0
fi
[[ "$EUID" == 0 ]] || { echo 'Run with sudo'; exit 1; }
if [[ "$MODE" == --undo ]]; then
  [[ "$CURRENT" != "$ORIGINAL" ]] || { echo 'Original driver already active on disk'; exit 0; }
  [[ -f "$STATE/installed.sha256" && "$CURRENT" == "$(cat "$STATE/installed.sha256")" ]] || { echo 'Current driver differs from this test; refusing undo'; exit 1; }
  [[ "$(sha "$STATE/previous.bundle/$BIN")" == "$ORIGINAL" ]] || { echo 'Original backup hash mismatch'; exit 1; }
  # Both paths are on the system Data volume. Atomic exchange preserves mapped files.
  swap "$BUNDLE" "$STATE/previous.bundle"
  echo 'Original 1.14.0 bundle restored. Reboot to activate it.'
  exit 0
fi
[[ "$MODE" == install ]] || { echo 'Usage: install (default), --check, or --undo'; exit 1; }
if [[ -f "$STATE/installed.sha256" && "$CURRENT" == "$(cat "$STATE/installed.sha256")" ]]; then
  echo 'PR #139 candidate is already installed on disk. Reboot to activate it.'
  exit 0
fi
[[ "$CURRENT" == "$ORIGINAL" ]] || { echo 'Expected the collected 1.14.0 driver; current hash differs. Refusing replacement.'; exit 1; }
[[ "$(cat /Library/NullMoth/driver-version)" == 1.14.0 ]] || { echo 'Driver version changed; refusing replacement'; exit 1; }
[[ ! -e "$STAGE" && ! -e "$STATE/previous.bundle" ]] || { echo 'A staged bundle or previous test exists; inspect it before proceeding'; exit 1; }
[[ "$(sha "$SOURCE")" == "$CANDIDATE" ]] || { echo 'Candidate hash mismatch'; exit 1; }
codesign --verify --strict "$SOURCE"
mkdir -p "$STATE"
trap 'if [[ -d "$STAGE" ]]; then rm -rf "$STAGE"; fi' EXIT
ditto "$BUNDLE" "$STAGE"
cp "$SOURCE" "$STAGE/$BIN"
[[ "$(sha "$STAGE/$BIN")" == "$CANDIDATE" ]] || { echo 'Staged executable hash mismatch'; exit 1; }
chown -R root:wheel "$STAGE"
chmod 755 "$STAGE/$BIN"
# Preserve the vendor bundle layout. The standalone candidate's code signature
# was verified above, and its complete signed bytes were checked after copying.
sha "$STAGE/$BIN" > "$STATE/installed.sha256"
printf '%s\n' 'https://github.com/nullmoth/nvidia-macos-driver/pull/139' '68b4ce209a32135385ec4b27221fc8c2cecfc484' > "$STATE/provenance.txt"
swap "$BUNDLE" "$STAGE"
# STAGE now holds the exact original bundle, including its original signature.
trap - EXIT
mv "$STAGE" "$STATE/previous.bundle"
[[ "$(sha "$BUNDLE/$BIN")" == "$(cat "$STATE/installed.sha256")" ]]
echo 'DONE: PR #139 release candidate installed on disk; running processes still use their mapped driver.'
echo 'Reboot, then collect the same workload with macos-ws-system-collect.sh.'
echo 'Undo: sudo bash /Users/thanhnndev/develop/projects/ga403wm-hackintosh/scripts/macos-ws-upload-install.sh --undo'

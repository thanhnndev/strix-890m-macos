#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Local fix for NullMoth NVRMFB 1.13.0: clear newly granted VRAM with 8-byte stores instead of 1-byte stores.
# Same idea as upstream PR nullmoth/nvidia-macos-driver#64 (not merged as of 2026-10-11). RUN ON macOS (asks for sudo).
#
#   scripts/macos-nullmoth-vramclear.sh           patch, rebuild the auxiliary kernel collection, then reboot yourself
#   scripts/macos-nullmoth-vramclear.sh --check   only verify that the installed NVRMFB is the expected 1.13.0 binary
#   scripts/macos-nullmoth-vramclear.sh --undo    put the original NVRMFB back and rebuild the collection
#
# What changes: 49 bytes of NVRMNVDAFramebuffer::vramGrant at file offset 0xe55b (the clear of the new block and the
# write/read-back probe of its first 8 bytes):
#   before: mov -0x128(%rbp),%r13; xor %eax,%eax; mov %r13,%rdi; mov %r12,%rcx; rep stosb
#           movabs $0x5a5aa5a5c0ffee01,%rax; mov %rax,(%r13); mov %r12,%rcx; mov (%r13),%r12; movq $0,(%r13); cmp %rax,%r12
#   after:  mov -0x128(%rbp),%r13; mov %r13,%rdi; mov %r12d,%ecx; shr $3,%ecx; xor %eax,%eax; rep stosq
#           movabs $0x5a5aa5a5c0ffee01,%rdi; mov %rdi,(%r13); mov %r12,%rcx; mov (%r13),%r12; mov %rax,(%r13); cmp %rdi,%r12
# Memory written, rcx, r12, r13 and the flags for the following jne are identical (checked in a user-space harness for
# 64 KB .. 16 MB). rax and rdi differ afterwards; both are overwritten before use on both paths after the jne. The size is a
# multiple of 64 KB (vramGrant rounds it), so the 8-byte count has no tail, and below 4 GB (the BAR1 grant budget).
set -euo pipefail
EXT=/Library/Extensions/NVRMFB.kext
BIN=$EXT/Contents/MacOS/NVRMFB
AUX=/Library/KernelCollections/AuxiliaryKernelExtensions.kc
ST=/Library/NullMoth/vramclear
OFF=$((0xe55b))
SHA_ORIG=a2a3cf961df1aae8                     # first 16 hex digits of the 1.13.0 NVRMFB binary
ORIG=4c8badd8feffff31c04c89ef4c89e1f3aa48b801eeffc0a5a55a5a498945004c89e14d8b650049c74500000000004939c4
NEW=4c8badd8feffff4c89ef4489e1c1e90331c0f348ab48bf01eeffc0a5a55a5a49897d004c89e14d8b6500498945004939fc
MODE=${1:-patch}

[ -f "$BIN" ] || { echo "NVRMFB is not installed ($BIN)"; exit 1; }
cur_bytes() { xxd -p -s $OFF -l 49 "$BIN" | tr -d '\n'; }
sha16() { shasum -a 256 "$1" | cut -c1-16; }

rebuild() {
  local K=/System/Library/Kernels/kernel KARG=(--allow-missing-kdk)
  [ -f "$K" ] && KARG+=(--kernel "$K")
  sudo kmutil create -n aux --volume-root / "${KARG[@]}" -B /System/Library/KernelCollections/BootKernelExtensions.kc \
    -S /System/Library/KernelCollections/SystemKernelExtensions.kc --repository /Library/Extensions -A "$AUX" -z \
    > /tmp/nullmoth-vramclear-kmutil.log 2>&1 || { echo "kmutil failed (log /tmp/nullmoth-vramclear-kmutil.log)"; return 1; }
  local ins; ins=$(kmutil inspect -a x86_64 -A "$AUX" 2>/dev/null)
  for k in NVRM NVAccel NVRMFB NVRMAGDC; do
    echo "$ins" | grep -q "com.nullmoth.$k" || { echo "com.nullmoth.$k missing from the new collection"; return 1; }
  done
  echo "auxiliary kernel collection rebuilt with all four NullMoth kexts"
}

case "$MODE" in
--check)
  b=$(cur_bytes)
  if [ "$b" = "$NEW" ]; then echo "NVRMFB is already patched (8-byte clear)"
  elif [ "$b" = "$ORIG" ] && [ "$(sha16 "$BIN")" = "$SHA_ORIG" ]; then echo "NVRMFB 1.13.0, unpatched: the patch applies"
  else echo "NVRMFB is not the 1.13.0 binary this patch was made for: do not patch"; exit 1; fi;;
--undo)
  [ -d "$ST/NVRMFB.kext" ] || { echo "no backup in $ST"; exit 1; }
  sudo -v
  sudo rm -rf "$EXT"; sudo ditto "$ST/NVRMFB.kext" "$EXT"
  sudo chown -R root:wheel "$EXT"; sudo chmod -R go-w "$EXT"
  if rebuild; then echo "original NVRMFB back; reboot to load it"
  else sudo cp -p "$ST/AuxiliaryKernelExtensions.kc" "$AUX"; echo "kmutil failed: the previous collection was put back"; exit 1; fi;;
patch)
  b=$(cur_bytes)
  [ "$b" = "$NEW" ] && { echo "already patched"; exit 0; }
  [ "$b" = "$ORIG" ] && [ "$(sha16 "$BIN")" = "$SHA_ORIG" ] || { echo "NVRMFB is not the expected 1.13.0 binary: nothing changed"; exit 1; }
  sudo -v
  sudo mkdir -p "$ST"
  [ -d "$ST/NVRMFB.kext" ] || sudo ditto "$EXT" "$ST/NVRMFB.kext"
  sudo cp -p "$AUX" "$ST/AuxiliaryKernelExtensions.kc"
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  ditto "$EXT" "$T/NVRMFB.kext"
  /usr/bin/python3 -I - "$T/NVRMFB.kext/Contents/MacOS/NVRMFB" "$OFF" "$ORIG" "$NEW" <<'PY'
import sys
path, off, orig, new = sys.argv[1], int(sys.argv[2]), bytes.fromhex(sys.argv[3]), bytes.fromhex(sys.argv[4])
d = bytearray(open(path, "rb").read())
assert len(orig) == len(new) == 49 and d[off:off + 49] == orig and d.count(orig) == 1
d[off:off + 49] = new
open(path, "wb").write(d)
PY
  [ "$(xxd -p -s $OFF -l 49 "$T/NVRMFB.kext/Contents/MacOS/NVRMFB" | tr -d '\n')" = "$NEW" ] || { echo "patch did not verify"; exit 1; }
  sudo rm -rf "$EXT"; sudo ditto "$T/NVRMFB.kext" "$EXT"
  sudo chown -R root:wheel "$EXT"; sudo chmod -R go-w "$EXT"
  if rebuild; then
    echo "patched. Reboot to load it. Measure with scripts/macos-vramtest.sh before/after. Undo: $0 --undo"
  else
    sudo rm -rf "$EXT"; sudo ditto "$ST/NVRMFB.kext" "$EXT"; sudo cp -p "$ST/AuxiliaryKernelExtensions.kc" "$AUX"
    echo "kmutil failed: original NVRMFB and collection put back, nothing changed"; exit 1
  fi;;
*) echo "usage: $0 [--check|--undo]"; exit 2;;
esac

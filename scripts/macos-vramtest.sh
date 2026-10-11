#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause-Clear
# Copyright (c) 2026 thanhnndev and contributors
# Times NullMoth's VRAM grant path (NVRMFB vramGrant, the call WindowServer makes for every new IOSurface): grants one 8 MB
# block through debug.nvrmfb_vramtest and releases it again, 5 times. RUN ON macOS (sudo for the sysctl writes).
# Upstream PR nullmoth/nvidia-macos-driver#64 measured ~180 ms per grant before (byte-wise VRAM clear) and ~30 ms after.
set -u
sysctl -n debug.nvrmfb_vramtest >/dev/null 2>&1 || { echo "debug.nvrmfb_vramtest not present (NullMoth NVRMFB not loaded?)"; exit 1; }
sudo -v || exit 1
for i in 1 2 3 4 5; do
  t0=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
  sudo sysctl -w debug.nvrmfb_vramtest=1 >/dev/null
  t1=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
  sudo sysctl -w debug.nvrmfb_vramtest=0 >/dev/null
  t2=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
  b=$(perl -e "printf '%.1f', ($t1-$t0)*1000"); r=$(perl -e "printf '%.1f', ($t2-$t1)*1000")
  echo "grant 8 MB: ${b} ms   release: ${r} ms   (each includes ~10-20 ms of sudo/sysctl start-up)"
done
# baseline: the same sudo + sysctl round trip on a read-only value
t0=$(perl -MTime::HiRes=time -e 'printf "%.6f", time'); sudo sysctl -n kern.ostype >/dev/null; t1=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
echo "baseline sudo+sysctl: $(perl -e "printf '%.1f', ($t1-$t0)*1000") ms"

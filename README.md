# strix-890m-macos

Radeon 890M (AMD Strix Point iGPU, `1002:150e`) on macOS, on the **ASUS ROG Zephyrus G14 (GA403WM)**: research notes, the
boot-display kexts, tooling and the trace logs of an attempt to put WindowServer on the iGPU.

> **Research, not a finished driver.** Nothing here gives you an accelerated 890M. The laptop's OLED hangs off the 890M, the
> RTX 5060 is driven by a third-party NVIDIA driver, and macOS has no Metal device for the AMD side. The work is a long
> series of numbered steps (`Step01` ... `Step72`) in [docs/890M-TRACE.md](docs/890M-TRACE.md) and
> [docs/890M-SESSION-HANDOFF.md](docs/890M-SESSION-HANDOFF.md). The kexts run in the kernel: read them before you install
> anything and keep a way to boot without them.

Part of the [GA403WM Hackintosh](https://github.com/thanhnndev/ga403wm-hackintosh) project (OpenCore EFI and index of the
parts). Siblings: [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) (Wi-Fi, Bluetooth),
[rog-control-macos](https://github.com/thanhnndev/rog-control-macos) (profiles, fans, lighting).

## Goal and state

The owner's goal (from [docs/890M-ROADMAP.md](docs/890M-ROADMAP.md), 2026-10-18): a full port of the 890M on macOS Tahoe,
independent of NullMoth, with WindowServer composited on the iGPU. That is what removes the 500-900 % WindowServer CPU
([docs/WINDOWSERVER-CPU.md](docs/WINDOWSERVER-CPU.md)), which comes from CoreAnimation's software rasteriser when no Metal
device exists. The roadmap's milestones, as of that audit:

| # | Milestone | State then |
|---|---|---|
| M1 | Own kernel driver brings up the 890M, DRM nodes, IB execution, compute | done |
| M2 | Graphics jobs reliable (gfx ring, VM, fences) | in progress |
| M3 | A non-headless accelerator so WindowServer gets a Metal device and presents | audited |
| M4 | Own userland (libdrm, RADV, then a Metal driver) | not started |
| M5 | Remove the NullMoth kernel binaries | after M3 and M4 |

Later steps are in the handoff and trace docs; the last commit of this history (Step72, 2026-10-26) is about WindowServer
reading NVIDIA's `debug.nvaccelfb` and a plugin that carries the 780M AMD fixes. Read the newest "Latest override" entry of
the handoff for where things stand; this README is not updated per step.

## What is in it

| Part | Where | What it does |
|---|---|---|
| `StrixGOP.kext` | `kexts/StrixGOP` | Framebuffer that adopts the boot GOP raster, plus OLED brightness through DPCD over DCN35's DPAUX engine |
| `StrixAccel.kext` | `kexts/StrixAccel` | Display-only accelerator (IOAccelerator / display pipe) so CoreDisplay can attach the framebuffer |
| `StrixMetalGate.kext` | `kexts/StrixMetalGate` | Gives WindowServer a Metal device when the only display is not on the NVIDIA GPU |
| `StrixHeadroom.kext` | `kexts/StrixHeadroom` | Lilu plugin removing the lock contention in `CoreDisplay::Display::CurrentHeadroom()` |
| `StrixProbe.kext` | `kexts/StrixProbe` | Opt-in diagnostic service, never a GPU driver |
| ABI data | `abi/strix`, `include/StrixNativeABI.h` | IOAccelerator profile of macOS 24H32 and the native ABI header |
| Patches | `patches/nmx` | Patch against the NullMoth sources (see [NOTICE.md](NOTICE.md) for the license) |
| Tooling | `tools/`, `scripts/` | Metal/Vulkan probes (`tools/890m`), Linux-side traces, install and collect scripts, host tests in `test/` |

## Build

On macOS with the Xcode command line tools (kexts cannot be built on Linux):

```bash
bash scripts/build.sh                 # all five kexts into build/
bash scripts/build.sh StrixGOP        # one kext
```

StrixHeadroom clones the Lilu headers into `build/Lilu` on first use. CI builds the same on `macos-14`.
Install scripts are `scripts/macos-strix-*-install.sh`; most of them expect the OpenCore ESP and a reboot.

## Branches

* `main`: the 890M research line (was `research/890m-cobalt64` in the EFI repo).
* `dev/tahoe-igpu`: the iGPU line that was `awdl/tahoe-igpu` in the EFI repo, filtered to these paths.

The history of these files was split out of `thanhnndev/ga403wm-hackintosh` with `git filter-repo`; commits keep their
original dates and authors. Files that were not part of the 890M work (Wi-Fi, Bluetooth, ROG Control) are not here.

## License

[Clear BSD](LICENSE) for the code written in this repo. See [NOTICE.md](NOTICE.md) for the parts that are not.

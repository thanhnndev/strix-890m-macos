# NullMoth driver: what we know (2026-10-11)

Source of this page: the installer scripts and the kext/bundle binaries on the macOS volume, read from Linux
(`strings`, `llvm-objdump`, plists), plus one `sample WindowServer`. Nothing here was verified by running the
driver under a debugger. Anything marked **unknown** is a gap, not a conclusion.

Rules that apply (see `HANDOFF.md`): do not disable the driver and do not guess at boot-args/quirks. The goal is a
working NullMoth driver; a change needs a root cause and the owner's agreement.

## Components

| Piece | What it is |
|---|---|
| `NVRM.kext` | NVIDIA open-gpu-kernel-modules 610.57.04 ported to XNU. Boots GSP-RM on the RTX 5060. |
| `NVRMFB.kext` | Display framebuffer (NVKMS underneath). Publishes timings/flip path to WindowServer. |
| `NVAccel.kext` | `IOAccelerator` + Metal plugin glue. |
| `NVRMAGDC.kext` | AGDC (graphics-driver control) personality. |
| `NVMTLDriver.bundle` | Metal driver in user space: Metal calls translated to Vulkan, using Mesa NVK (`nvkmd_nvrm` backend, Mesa 26.3.0-devel). |
| `NVIDIAShared.bundle` | AIR -> NVVM -> PTX -> sm_120 JIT. Uses NVIDIA's closed `nvvm`/`ptxjit` libraries. |
| `/Library/NullMoth/` | Installer state, `nullmoth-setup.sh`, recover daemon, allow-list. |

Kexts sit in `/Library/Extensions` and load from the auxKC built with `kmutil create -n aux`. Installed record on the
volume says driver version 1.9.0 on macOS 15 (the strings dump in older notes was 1.0.8).

## What the installer touches

* `config.plist`: ResizeGpuBars 13, ResizeAppleGpuBars -1, `Kernel/Block` IONDRVSupport, SIP `0x0A43`
  (`csr-active-config`), SecureBootModel Disabled, boot-args. A backup `config.plist.nullmoth-<time>` is made first.
* `--remove` restores from that backup. `nullmoth-setup.sh --collect-logs DIR` is a read-only collector.
* **Never run the 1401.exe "Build" afterwards**: it overwrites the ESP `config.plist`.

## Process allow-list (`/Library/NullMoth/nvmtl-allow.txt`)

One name per line. `*` = every process, `-Name` = denied, `!Name` = armed only while `debug.nvaccelfb` is non-zero.
Current content: `*` and `!WindowServer`. So everything uses the Metal translation layer and WindowServer is
armed only when the framebuffer sysctl is set.

## Logging

Only lines containing `FAIL` or `REFUS` reach syslog, prefixed `NullMoth:` and rate-limited per call site. An empty
`log show` therefore means "nothing failed", not "nothing happened". `NVRM-fb:` lines are NVRMFB info lines.

## Sysctl counters (read-only, no sudo)

`debug.nvaccelfb`, `debug.nvaccel_iop`, `debug.nvaccel_iop_async`, `debug.nvaccel_iop_flip`,
`debug.nvaccel_heads_published`, `debug.nvaccel_crc`, `debug.nvrmfb_agdc`, `debug.nvrmfb_agdc_k5`,
`debug.nvrmfb_flip_*`, `debug.nvrm_pageoff_*`. The probe script dumps all of them (`scripts/macos-nullmoth-probe.sh`).

Boot-arg switches found in the binaries (reference only, do not toggle): `-nvoff`, `-nvrmnogo`, `-nvrmnoflip`,
`-nvrmnobootscreen`, `-nvkmsnosmooth`, `-nvfbsurvey`, `nvhwvbl=0`, `nvcursor=0`, `nvhud=1`, `nvfbsample=1`,
`nvfb=1`, `nvaccel=1`, `nvaccelfb=1|3|4`.

Environment knobs of the user-space driver (read by `NVMTLDriver`; they are per-process environment and WindowServer
is launched by launchd, so they are not an easy lever): `NVMTL_NO_SURFACE_SHARE`, `NVMTL_NO_NOCOPY`,
`NVMTL_NO_SURFACE_PAGEOFF`, `NVMTL_SHARED_VRAM`, `NVMTL_SHARED_VRAM_BUDGET_MB`, `NVMTL_NO_FPS`, `NVMTL_PERF_LOG`,
`NVMTL_PSTAT`, `NVMTL_NVK_MESSAGES`, `NVMTL_VRAM_HEADROOM_MB`, `NVMTL_RES2_*`, `NVMTL_SPVCACHE_*`, `NVK_DEBUG`,
`NVK_DIAG`, `NVRM_GSUB_LOG`, `NVRM_XNU_TRACE`, ... (about 100 `NVMTL_*`, 40 `NVK_*`, 10 `NVRM_*`).

## Desktop lag: hypothesis (not confirmed)

`windowserver-sample.txt` (idle desktop, 6.7 s): WindowServer is about 95 % blocked in `mach_msg`, so it is not CPU
bound. The work it does is on the render path:

`CA::OGL::MetalContext::draw` -> `-[NVMTLRenderCommandEncoder setFragmentTexture:]` -> `-[NVMTLTexture nvmtlSurfaceIn]`
-> `nvmtl_vk_image_write` -> `memmove`, plus `vk_WaitForFences` -> `nvrm_gsub_wait`.

Reading of the disassembly: an IOSurface-backed texture is either
1. in a family-shared VRAM image (zero copy), or
2. a per-process private image that is filled by a CPU `memmove` on bind (`nvmtlSurfaceIn`).

The sample shows path 2 for WindowServer's textures. If it is always path 2, every composited surface is copied per
frame at 2880x1800 which would explain a laggy but not CPU-saturated desktop. What is **unknown**:

* whether this path is taken for every bind or only for first use of a surface,
* the active mode (60 vs 120 Hz, HiDPI) of the current boot,
* whether the sysctl counters (`debug.nvaccel_iop*`, `debug.nvrmfb_flip_*`, `debug.nvrm_pageoff_*`) show copies vs
  zero-copy flips.

Data needed: run `bash scripts/macos-nullmoth-probe.sh --window` on macOS and drag a window during the 5 s sample.
Compare the counters before and after.

If the cause is the copy path, the fix belongs in the driver (the vendor), not in our config. Report it upstream with
the sample and counters rather than changing quirks here.

## Other things seen, effect unknown

* `kernelmanagerd` "restricted lookup table" errors were seen in the log of the same boot.
* Shutdown-stall reports exist in DiagnosticReports.
* Neither has been tied to a user-visible problem.

## Recovery paths

* OpenCore picker tool **"1401: Remove NVIDIA driver"** (`EFI/OC/Tools/NullMothSafe.efi`, FullNvramAccess): sets the
  NVRAM variable `7C436110-AB2A-4BBB-A880-FE41995C9F82:nullmoth-remove`. At the next macOS start the recover daemon
  (`/Library/NullMoth/nullmoth-recover.sh`) clears the variable, runs `nullmoth-setup.sh --remove`
  (log: `/Library/NullMoth/recover.log`) and reboots. It needs macOS to reach userspace, so it is not a fix for a
  panic-at-boot.
* `--remove` restores the original config from `EFI/OC/config.plist.nullmoth-*` and removes the kexts.
* `1401 --crash-check` is only a UI that asks before sending anything.

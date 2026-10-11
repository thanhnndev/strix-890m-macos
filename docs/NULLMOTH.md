# NullMoth driver: what we know (2026-10-11)

**Read the vendor's source first.** The driver is published with source at
<https://github.com/nullmoth/nvidia-macos-driver> (PolyForm Noncommercial; release notes in `docs/RELEASE-*.md`). The
first pass of this page was derived from the installed binaries (`strings`, `llvm-objdump`) and a `sample
WindowServer`; that was the wrong starting point, and the lag hypothesis it produced was not the best lead. The
component and recovery sections below stay valid; the lag section was replaced (2026-10-11).

Installed here: **1.9.0** (2026-10-10). Latest release: **1.12.0** (2026-10-11 03:26Z). Nothing here was verified by
running a newer driver.

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

## Desktop lag and 120 Hz: what changed between 1.9.0 and 1.12.0

Read from `git compare v1.9.0...v1.12.0` (39 commits). These are the changes that touch what we saw:

| Release | Commit | Change | Relevance |
|---|---|---|---|
| 1.10.0 | `3619f95e` | `cursorApply()` used to name the primary surface too, so **every cursor move was also a primary flip, paced to vsync**, and an older frame could go back on the panel ("flash on mouse movement"). Now cursor-only commits. | Matches a laggy pointer/desktop on 1.9.0. |
| 1.10.0 | `223555ff` | `addKmsRefreshModes`: also offers rasters NVKMS validated that macOS never proposed, e.g. **modes that exist only in the EDID's DisplayID block (most 100-240 Hz modes, issue #29)**. | Our panel's 120 Hz mode is DisplayID-only (see `HANDOFF.md` item 3). |
| 1.10.0 | `4cc045dc` | Managed no-copy buffers get a VRAM copy (were read across PCIe). | Throughput of image-heavy work. |
| 1.10.0 | `db2e966e` | Flicker workaround restarts WindowServer only at the login window. | Black screen after the restart on auto-login. |
| 1.10.0 | `51546402` | Setup requires **Lilu + AMFIPass** on. Without AMFIPass, WindowServer (platform binary) refuses the ad hoc signed driver: "mapping process is a platform binary, but mapped file is not", no Metal device, black screen with a cursor. | Our `Kernel/Add` has Lilu but **no AMFIPass.kext**. |
| 1.11.0 | `9a20289a` | Setup adds boot-arg `ipc_control_port_options=0` (Firefox crashes at launch with AMFI relaxed). | Missing from our boot-args. |
| 1.12.0 | tracker | Display tracker writes `/Library/NullMoth/display-trace/{trace,kernel,ws}.txt` from the first second of every boot (per-second driver counters, refresh rate per framebuffer, WindowServer starts, EDID). Survives a forced restart. | Exactly the evidence the black-screen-above-60 Hz case needs. |

What this changes in the plan:

* The previous "copy path" hypothesis (CPU `memmove` in `nvmtlSurfaceIn`) is **not** the leading explanation any more.
  The driver's own commit message on `3619f95e` names the cursor-flip as the cause of a visible artefact, and the
  1.12 notes describe the IOSurface copy path only for the headless (Optimus) case, not ours.
* The macOS display override in `macos/display-override/` (EDID with a 120 Hz base DTD) works around something the
  driver now handles itself. Remove it (`scripts/install-display-override.sh --undo`) when testing 1.12 so only one
  variable changes.
* Open at 1.12.0 per the vendor: "black screen or flicker above 60 Hz on some monitors". That is our 120 Hz black
  screen; the vendor's route is the display tracker plus "Send logs" (uploads to NullMoth; the owner decides).

The unknowns that remain: whether 1.12.0 actually keeps our panel at 120 Hz, and whether the lag is gone. Both need a
run on the machine.

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

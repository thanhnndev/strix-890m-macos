# WindowServer CPU investigation — 2026-10-11

Machine: GA403WM, macOS 15.8.1 (24H32), NullMoth 1.14.0. The owner reports high CPU even without scrolling or dragging.

## Measured result

WindowServer's CPU load follows visible application content. Temporarily hiding the ChatGPT application (which hosts
Codex here) reduces the measured load almost to idle. This is the strongest lead, rather than a driver busy loop that
continues with all windows hidden. The driver still contributes substantial work when that content changes.

CPU below is the change in cumulative WindowServer process CPU time divided by elapsed wall time, expressed as a
percentage of **one logical CPU**. These are separate short measurements, not a simultaneous benchmark.

| State | Duration | CPU | Primary flips/s |
|---|---:|---:|---:|
| Visible windows | 10.11 s | 78.9% | 29.8 |
| Previously visible regular applications hidden | 10.12 s | 12.3% | 3.8 |
| Same applications restored | 10.11 s | 73.7% | 35.4 |
| Only ChatGPT hidden | 8.57 s | 1.5% | 1.2 |
| Only Microsoft Edge hidden | 8.58 s | 53.0% | 34.2 |
| Only Zalo hidden | 8.57 s | 65.9% | 34.4 |

The hide-all test affected Zalo, Microsoft Edge, ChatGPT and Finder; Claude was already hidden. Every application
hidden by the test was unhidden afterward. Tests ran during an active Codex conversation, so streaming responses/tool
activity can contribute. This establishes dependence on that visible window, but does not identify a particular
animation or prove that the same repaint rate persists after the conversation finishes. Repeat with no active turn
before calling it a persistent application defect.

During the visible/hidden/restored test, most updates were on driver head 1 (296/301, 32/38 and 352/358 respectively).
Head counters are driver indices; they have not been mapped to a physical display here. No new `iop_fail` or
`iop_async_drop` occurred during these measurements.

## Original sample and driver source

Original data was collected at 21:03 local, WindowServer PID 158, then preserved at
`~/efi-audit/ws-cpu-20261011/` (`ws-sample.txt`, both vmmap summaries and `ab.json`).

The main thread has 2,485 observations. Its dominant update path is:

`CGXUpdateDisplay → CompositorMetal → QuartzCore → NVMTLTexture nvmtlSurfaceIn → nvmtl_vk_image_write`

The large upload branch contains 410 observations in `longcopy` and 91 in upload submission/wait. Other threads
show `nvmtlSurfaceOut → nvmtl_vk_image_read` and IOSurface release. These are observations of elapsed execution/wait
states, **not CPU percentages**; parent and child counts overlap and must not be summed. Sleeping syscall counts
across all threads do not indicate CPU consumed in those syscalls.

Source checked at tag `v1.14.0`, commit `56ae15f4e91a8ef0bf7a9db6f6980a0a49a0bf8f`:

* [NVMTLObjects.m](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.14.0/plugin/NVMTLObjects.m):
  `nvmtlSurfaceIn` skips an already synchronized, unchanged IOSurface seed/generation. Actual uploads can result from
  changed or newly created surfaces; this sample cannot distinguish those cases. `commitAndWaitUntilSubmitted` waits
  for completion in WindowServer deliberately so scanout cannot precede rendering.
* [nvmtl_vk.c](https://github.com/nullmoth/nvidia-macos-driver/blob/v1.14.0/plugin/nvmtl_vk.c):
  `nvmtl_vk_image_write` copies pixels into staging memory and submits/waits for a Vulkan transfer. The readback path
  also copies pixels. The sample proves these paths were used, but does not establish why VRAM sharing did not avoid
  each individual transfer.

Memory footprint went from 680 to 692 MB across 13.2 seconds; peak stayed 868.4 MB. IOKit grew by 11.8 MB, IOSurface
dirty memory stayed 195.4 MB, malloc dirty stayed about 161 MB. This short interval is insufficient evidence of a
memory leak. Large framebuffer virtual reservations are not equivalent to allocated RAM.

## Practical mitigation and follow-up

Hide/minimize the ChatGPT/Codex window when it is not in use: this directly reduced WindowServer load in the test.
No driver removal, boot arguments, refresh-rate changes, or WindowServer restart are required for this mitigation.

For a clean repeat, launch the following from Terminal while no Codex response is running. Keep the pointer still,
leave the same displays connected, and take each measurement once with the app visible and once minimized:

```sh
python3 scripts/macos-ws-cpu.py --seconds 20 --label visible-static
python3 scripts/macos-ws-cpu.py --seconds 20 --label chatgpt-minimized
```

The collector needs no sudo, changes no settings, and saves JSON under `~/efi-audit/ws-cpu-<timestamp>/`.
It checks that WindowServer did not restart, measures CPU from process-time deltas, and records per-head updates,
flip/error/drop and allocation counter deltas. Allocation counters are cumulative driver-wide totals, not solely
WindowServer allocations. Do not interpret a decreasing live-allocation count or cumulative byte total as a leak.

If the load remains high with ChatGPT minimized in a quiet repeat, collect a new WindowServer sample in that state
with `scripts/macos-ws-frame-sample.sh` (sudo needed). Further driver changes need that evidence. Removing the completion
wait or forcing a sharing knob without checking synchronization risks stale/black frames and is not a justified fix.

No upstream issue or message has been sent. A full driver-side optimization is still unproven; this investigation
provides a measured mitigation and a reproducible way to separate application repaint load from background load.

// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Lists the built-in display's modes and switches to a true HiDPI mode (points = pixels / 2) with an automatic revert.
// A HiDPI mode keeps the panel's native framebuffer (2880x1800), so NVRMFB does no scaled mode set; the low-resolution
// "1440 x 900" mode does, and that one goes black on NullMoth 1.13 (see docs/HANDOFF.md item 7). This tool never picks a
// mode whose pixel size differs from the native one.
// Build: swiftc -O tools/hidpi-try.swift -o /tmp/hidpi-try
// Run:   /tmp/hidpi-try list [--all]    desktop modes (--all: also the hidden ones), HiDPI ones marked
//        /tmp/hidpi-try 1440            switch to "looks like 1440 x 900" (HiDPI) for this session; press Return within 15 s
//                                       to keep it, otherwise (black screen, nothing typed) it goes back by itself
//        /tmp/hidpi-try 1440 --keep     same, and once confirmed make it the saved setting (survives log out / reboot)
import CoreGraphics
import Foundation

let d = CGMainDisplayID()
let all = (CGDisplayCopyAllDisplayModes(d, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode]) ?? []
guard let cur = CGDisplayCopyDisplayMode(d) else { print("no display mode"); exit(1) }
let nativeW = all.map(\.pixelWidth).max() ?? cur.pixelWidth
func desc(_ m: CGDisplayMode) -> String {
    String(format: "id 0x%08x  looks like %4dx%-4d  pixels %4dx%-4d  %3.0f Hz  flags 0x%08x%@%@", m.ioDisplayModeID, m.width,
           m.height, m.pixelWidth, m.pixelHeight, m.refreshRate, m.ioFlags, m.pixelWidth == 2 * m.width ? "  HiDPI" : "",
           m.isUsableForDesktopGUI() ? "" : "  (hidden: not usable for the desktop)")
}
let args = CommandLine.arguments
if args.count < 2 || args[1] == "list" {
    print("current: " + desc(cur))
    // flags: 0x00800000 valid for HiRes, 0x00200000 valid for mirroring (alone: mirror-only), 0x02000000 native
    for m in all where m.isUsableForDesktopGUI() || args.contains("--all") { print("  " + desc(m)) }
    if !all.contains(where: { $0.pixelWidth == 2 * $0.width }) {
        print("no HiDPI mode is offered (WindowServer pref DisplayResolutionEnabled + the scale-resolutions override, then reboot)")
    }
    exit(0)
}
guard let want = Int(args[1]) else { print("usage: hidpi-try list | <logical width> [--keep]"); exit(2) }
let keep = args.contains("--keep")
let cands = all.filter { $0.width == want && $0.pixelWidth == 2 * $0.width && $0.pixelWidth == nativeW && $0.isUsableForDesktopGUI() }
guard let target = cands.max(by: { $0.refreshRate < $1.refreshRate }) else {
    print("no HiDPI mode that looks like \(want) wide with the native \(nativeW)-pixel framebuffer; nothing changed"); exit(1)
}
func apply(_ m: CGDisplayMode, _ opt: CGConfigureOption) -> Bool {
    var c: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&c) == .success else { return false }
    CGConfigureDisplayWithDisplayMode(c, d, m, nil)
    return CGCompleteDisplayConfiguration(c, opt) == .success
}
print("switching to " + desc(target) + " (was " + desc(cur) + ")")
guard apply(target, .forSession) else { print("the switch was refused; nothing changed"); exit(1) }
print("press Return within 15 s to keep it")
var confirmed = false
let sem = DispatchSemaphore(value: 0)
DispatchQueue.global().async { if readLine() != nil { confirmed = true }; sem.signal() }
_ = sem.wait(timeout: .now() + 15)
if !confirmed {
    _ = apply(cur, .forSession)
    print("no answer: back to " + desc(cur)); exit(1)
}
if keep { print(apply(target, .permanently) ? "kept and saved" : "kept for this session (saving failed)") }
else { print("kept for this session (run again with --keep to save it)") }

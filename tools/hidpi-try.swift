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

// WindowServer's own mode table (private SkyLight calls; record layout as used by displayplacer, MIT). With the NullMoth
// framebuffer WindowServer does build HiDPI modes (density 2), including "1440 x 900" on the native 2880x1800 mode, but
// CGDisplayCopyAllDisplayModes leaves them out, so System Settings never offers them. These calls can still select them.
@_silgen_name("CGSGetNumberOfDisplayModes") func CGSGetNumberOfDisplayModes(_ d: CGDirectDisplayID, _ n: UnsafeMutablePointer<Int32>) -> CGError
@_silgen_name("CGSGetDisplayModeDescriptionOfLength") func CGSGetDisplayModeDescriptionOfLength(_ d: CGDirectDisplayID, _ i: Int32, _ p: UnsafeMutableRawPointer, _ len: Int32) -> CGError
@_silgen_name("CGSGetCurrentDisplayMode") func CGSGetCurrentDisplayMode(_ d: CGDirectDisplayID, _ i: UnsafeMutablePointer<Int32>) -> CGError
@_silgen_name("CGSConfigureDisplayMode") func CGSConfigureDisplayMode(_ c: CGDisplayConfigRef?, _ d: CGDirectDisplayID, _ i: Int32) -> CGError
struct WSMode { let index: Int32, id: UInt32, flags: UInt32, width: Int, height: Int, hz: Int, density: Float }
func wsModes(_ d: CGDirectDisplayID) -> [WSMode] {
    var n: Int32 = 0
    guard CGSGetNumberOfDisplayModes(d, &n) == .success else { return [] }
    var out: [WSMode] = []
    let buf = UnsafeMutableRawPointer.allocate(byteCount: 0xD4, alignment: 8); defer { buf.deallocate() }
    for i in 0..<n {
        memset(buf, 0, 0xD4)
        guard CGSGetDisplayModeDescriptionOfLength(d, i, buf, 0xD4) == .success else { continue }
        out.append(WSMode(index: i, id: buf.load(fromByteOffset: 0, as: UInt32.self), flags: buf.load(fromByteOffset: 4, as: UInt32.self),
                          width: Int(buf.load(fromByteOffset: 8, as: UInt32.self)), height: Int(buf.load(fromByteOffset: 0xC, as: UInt32.self)),
                          hz: Int(buf.load(fromByteOffset: 0xBE, as: UInt16.self)), density: buf.load(fromByteOffset: 0xD0, as: Float.self)))
    }
    return out
}
func wsDesc(_ m: WSMode) -> String {
    String(format: "ws #%-3d looks like %4dx%-4d  pixels %4dx%-4d  %3d Hz  flags 0x%08x%@", m.index, m.width, m.height,
           Int(Float(m.width) * m.density), Int(Float(m.height) * m.density), m.hz, m.flags, m.density == 2 ? "  HiDPI" : "")
}

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
    let ws = wsModes(d).filter { $0.density == 2 }
    if !ws.isEmpty {
        print("WindowServer HiDPI modes (hidden from System Settings; `hidpi-try <width>` selects them):")
        for m in ws { print("  " + wsDesc(m)) }
    } else if !all.contains(where: { $0.pixelWidth == 2 * $0.width }) {
        print("no HiDPI mode is offered (WindowServer pref DisplayResolutionEnabled + the scale-resolutions override, then reboot)")
    }
    exit(0)
}
guard let want = Int(args[1]) else { print("usage: hidpi-try list | <logical width> [--keep]"); exit(2) }
let keep = args.contains("--keep")
let cands = all.filter { $0.width == want && $0.pixelWidth == 2 * $0.width && $0.pixelWidth == nativeW && $0.isUsableForDesktopGUI() }
func confirm() -> Bool {
    print("press Return within 15 s to keep it")
    var ok = false
    let sem = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { if readLine() != nil { ok = true }; sem.signal() }
    _ = sem.wait(timeout: .now() + 15)
    return ok
}
func wsApply(_ i: Int32, _ opt: CGConfigureOption) -> Bool {
    var c: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&c) == .success else { return false }
    guard CGSConfigureDisplayMode(c, d, i) == .success else { CGCancelDisplayConfiguration(c); return false }
    return CGCompleteDisplayConfiguration(c, opt) == .success
}
if cands.isEmpty {
    // WindowServer's hidden HiDPI modes; only those whose backing is the native framebuffer (no scaled NVRMFB mode set)
    let ws = wsModes(d)
    var curIdx: Int32 = -1
    let wsc = ws.filter { $0.width == want && $0.density == 2 && Int(Float($0.width) * $0.density) == nativeW }
    // prefer the copy of the native mode (flag 0x02000000), then the highest refresh rate
    guard CGSGetCurrentDisplayMode(d, &curIdx) == .success,
          let t = wsc.max(by: { ($0.flags & 0x02000000, $0.hz) < ($1.flags & 0x02000000, $1.hz) }) else {
        print("no HiDPI mode that looks like \(want) wide with the native \(nativeW)-pixel framebuffer; nothing changed"); exit(1)
    }
    let was = ws.first { $0.index == curIdx }.map(wsDesc) ?? "ws #\(curIdx)"
    print("switching to " + wsDesc(t) + " (was " + was + ")")
    guard wsApply(t.index, .forSession) else { print("the switch was refused; nothing changed"); exit(1) }
    if !confirm() { _ = wsApply(curIdx, .forSession); print("no answer: back to " + was); exit(1) }
    if keep { print(wsApply(t.index, .permanently) ? "kept and saved" : "kept for this session (saving failed)") }
    else { print("kept for this session (run again with --keep to save it)") }
    exit(0)
}
let target = cands.max(by: { $0.refreshRate < $1.refreshRate })!
func apply(_ m: CGDisplayMode, _ opt: CGConfigureOption) -> Bool {
    var c: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&c) == .success else { return false }
    CGConfigureDisplayWithDisplayMode(c, d, m, nil)
    return CGCompleteDisplayConfiguration(c, opt) == .success
}
print("switching to " + desc(target) + " (was " + desc(cur) + ")")
guard apply(target, .forSession) else { print("the switch was refused; nothing changed"); exit(1) }
if !confirm() {
    _ = apply(cur, .forSession)
    print("no answer: back to " + desc(cur)); exit(1)
}
if keep { print(apply(target, .permanently) ? "kept and saved" : "kept for this session (saving failed)") }
else { print("kept for this session (run again with --keep to save it)") }

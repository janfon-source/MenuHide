// Renders MenuHide/AppIcon.icns.  Run from MenuHideMac/:  swift tools/make_icon.swift
// With a path (swift tools/make_icon.swift preview.png), writes a 512px preview there instead.
import AppKit

let backTop = NSColor(red: 0.420, green: 0.361, blue: 0.906, alpha: 1)
let backBottom = NSColor(red: 0.255, green: 0.200, blue: 0.663, alpha: 1)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: ~10% transparent margin around a rounded square.
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let square = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: backTop, ending: backBottom)!.draw(in: square, angle: -90)

    // The menu bar icon's magic wand, white, filling the middle of the square, on a layer of its
    // own so it can be painted white without painting the square.
    let layer = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer)
    // Drawn black, then painted white where it is, as a template image shows in the menu bar.
    let side = s * 0.56
    let wand = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: side, weight: .medium))!
    let fit = min(side / wand.size.width, side / wand.size.height)
    let size = NSSize(width: wand.size.width * fit, height: wand.size.height * fit)
    wand.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill(using: .sourceIn)
    NSGraphicsContext.restoreGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = backBottom.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.02
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    layer.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if CommandLine.arguments.count > 1 {
    try! render(512).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    exit(0)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MenuHide.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let out = URL(fileURLWithPath: "MenuHide/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")

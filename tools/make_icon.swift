// Renders MenuHide/AppIcon.icns.  Run from MenuHideMac/:  swift tools/make_icon.swift
// With a path (swift tools/make_icon.swift preview.png), writes a 512px preview there instead.
import AppKit

let backTop = NSColor(red: 0.420, green: 0.361, blue: 0.906, alpha: 1)
let backBottom = NSColor(red: 0.255, green: 0.200, blue: 0.663, alpha: 1)
let bar = NSColor(white: 1, alpha: 0.95)
let dim = NSColor(white: 1, alpha: 0.35)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: ~10% transparent margin around a rounded square.
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    NSGradient(starting: backTop, ending: backBottom)!
        .draw(in: NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)

    // A row of menu bar icons: the ones on the left fade away behind a chevron, the ones on
    // the right stay bright.
    let y = s * 0.5, r = s * 0.055
    for (i, x) in [0.24, 0.36].enumerated() {
        dim.withAlphaComponent(0.2 + 0.15 * CGFloat(i)).setFill()
        NSBezierPath(ovalIn: NSRect(x: s * x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }
    for x in [0.66, 0.78] {
        bar.setFill()
        NSBezierPath(ovalIn: NSRect(x: s * x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: s * 0.55, y: y + s * 0.11))
    chevron.line(to: NSPoint(x: s * 0.46, y: y))
    chevron.line(to: NSPoint(x: s * 0.55, y: y - s * 0.11))
    chevron.lineWidth = s * 0.045
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    bar.setStroke()
    chevron.stroke()

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

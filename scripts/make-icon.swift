// MIT License - Copyright (c) fintonlabs.com
//
// Draws the Capstand app icon — the website's blueprint look: a cobalt tile on
// a drafting grid, a white line-drawn phone on a stand. Regenerate with
// `make icon`; writes Assets/Capstand.icns and docs/icon.png.
import AppKit

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let s = CGFloat(size) / 1024   // everything is laid out on Apple's 1024 grid

    // Tile: 824pt rounded square centred on the canvas, per the macOS icon template.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: NSColor(white: 0, alpha: 0.3).cgColor)
    ctx.addPath(tilePath)
    ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.26, blue: 0.75, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.20, green: 0.40, blue: 0.93, alpha: 1).cgColor,
        NSColor(srgbRed: 0.07, green: 0.20, blue: 0.62, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // Drafting grid: minor every 48pt, major every 192pt. Skipped at tiny sizes.
    if size >= 64 {
        for (step, alpha, width) in [(48.0, 0.07, 1.5), (192.0, 0.14, 2.5)] {
            ctx.setStrokeColor(NSColor(white: 1, alpha: alpha).cgColor)
            ctx.setLineWidth(width * s)
            var v = tile.minX
            while v <= tile.maxX {
                ctx.move(to: CGPoint(x: v, y: tile.minY)); ctx.addLine(to: CGPoint(x: v, y: tile.maxY))
                ctx.move(to: CGPoint(x: tile.minX, y: v)); ctx.addLine(to: CGPoint(x: tile.maxX, y: v))
                v += step * s
            }
            ctx.strokePath()
        }
    }
    ctx.restoreGState()

    let white = NSColor.white.cgColor
    let line = max(2, 26 * s)
    ctx.setStrokeColor(white)
    ctx.setFillColor(white)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Phone: portrait, slightly above centre so the stand has room.
    let phone = CGRect(x: 372 * s, y: 300 * s, width: 280 * s, height: 530 * s)
    ctx.setLineWidth(line)
    ctx.addPath(CGPath(roundedRect: phone, cornerWidth: 60 * s, cornerHeight: 60 * s, transform: nil))
    ctx.strokePath()

    // Screen tint and Dynamic Island.
    let screen = phone.insetBy(dx: 30 * s, dy: 30 * s)
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 38 * s, cornerHeight: 38 * s, transform: nil))
    ctx.setFillColor(NSColor(white: 1, alpha: 0.16).cgColor)
    ctx.fillPath()
    ctx.setFillColor(white)
    let island = CGRect(x: phone.midX - 52 * s, y: screen.maxY - 44 * s, width: 104 * s, height: 26 * s)
    ctx.addPath(CGPath(roundedRect: island, cornerWidth: 13 * s, cornerHeight: 13 * s, transform: nil))
    ctx.fillPath()

    // Stand: a cradle lip under the phone and a base.
    ctx.setLineWidth(line)
    ctx.move(to: CGPoint(x: phone.midX, y: phone.minY - 14 * s))
    ctx.addLine(to: CGPoint(x: phone.midX, y: 222 * s))
    ctx.move(to: CGPoint(x: 322 * s, y: 222 * s))
    ctx.addLine(to: CGPoint(x: 702 * s, y: 222 * s))
    ctx.strokePath()

    // Annotation tick, the blueprint callout from the website.
    if size >= 64 {
        ctx.setLineWidth(max(1, 10 * s))
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.7).cgColor)
        ctx.move(to: CGPoint(x: phone.maxX + 20 * s, y: phone.maxY - 90 * s))
        ctx.addLine(to: CGPoint(x: 740 * s, y: phone.maxY - 90 * s))
        ctx.addLine(to: CGPoint(x: 790 * s, y: phone.maxY - 40 * s))
        ctx.strokePath()
    }
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Capstand.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: base * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 512).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Assets/Capstand.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Assets/Capstand.icns and docs/icon.png" : "iconutil failed")

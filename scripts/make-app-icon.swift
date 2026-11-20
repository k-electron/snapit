// Draws snapit's placeholder app icon into Shared/Assets.xcassets/AppIcon.appiconset.
// Run: swift scripts/make-app-icon.swift Shared/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    let inset = s * 0.08
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tile = NSBezierPath(roundedRect: body, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(
        starting: NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.88, alpha: 1))!
        .draw(in: tile, angle: -90)

    // Viewfinder corners.
    NSColor.white.setStroke()
    let corner = s * 0.16
    let box = body.insetBy(dx: s * 0.17, dy: s * 0.17)
    let path = NSBezierPath()
    path.lineWidth = s * 0.05
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    for (cx, cy, dx, dy) in [
        (box.minX, box.minY, 1.0, 1.0), (box.maxX, box.minY, -1.0, 1.0),
        (box.minX, box.maxY, 1.0, -1.0), (box.maxX, box.maxY, -1.0, -1.0),
    ] {
        path.move(to: NSPoint(x: cx + dx * corner, y: cy))
        path.line(to: NSPoint(x: cx, y: cy))
        path.line(to: NSPoint(x: cx, y: cy + dy * corner))
    }
    path.stroke()
    NSColor.white.setFill()
    let dot = s * 0.09
    NSBezierPath(ovalIn: NSRect(x: s / 2 - dot, y: s / 2 - dot, width: 2 * dot, height: 2 * dot)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: base * scale).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
        images.append([
            "idiom": "mac", "scale": "\(scale)x", "size": "\(base)x\(base)", "filename": name,
        ])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("Contents.json"))

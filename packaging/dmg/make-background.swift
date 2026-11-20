// Draws the DMG window background: an arrow from the snapit icon into Applications and the
// First open line. Nothing it draws is committed; scripts/make-dmg.sh runs it for every DMG.
//
// Run: swift packaging/dmg/make-background.swift OUT_DIR WIDTH HEIGHT APP_X APP_Y APPLICATIONS_X APPLICATIONS_Y
// Sizes and positions are in points, measured from the window's top left (the same numbers
// packaging/dmg/settings.py gives dmgbuild for the window and the two icon centres).
// Writes OUT_DIR/background.png (72 dpi) and OUT_DIR/background@2x.png (144 dpi).
import AppKit

let args = CommandLine.arguments
guard args.count == 8, let width = Double(args[2]), let height = Double(args[3]),
    let appX = Double(args[4]), let appY = Double(args[5]),
    let applicationsX = Double(args[6]), let applicationsY = Double(args[7])
else {
    FileHandle.standardError.write(
        Data("usage: make-background.swift OUT_DIR WIDTH HEIGHT APP_X APP_Y APPLICATIONS_X APPLICATIONS_Y\n".utf8))
    exit(2)
}
let outDir = args[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let caption = "First open: System Settings \u{203A} Privacy & Security \u{203A} Open Anyway"
let heading = "Drag snapit into Applications"
let iconRadius = 64.0  // half of icon_size in settings.py

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)  // 144 dpi for the 2x image
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    defer { NSGraphicsContext.restoreGraphicsState() }

    // AppKit's origin is bottom left; the numbers on the command line start at the top left.
    func y(_ fromTop: Double) -> CGFloat { CGFloat(height - fromTop) }
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    NSGradient(
        starting: NSColor(calibratedWhite: 0.97, alpha: 1),
        ending: NSColor(calibratedWhite: 0.88, alpha: 1))!.draw(in: bounds, angle: -90)

    let ink = NSColor(calibratedWhite: 0.22, alpha: 1)
    let centered = NSMutableParagraphStyle()
    centered.alignment = .center

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerY: Double) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: centered,
        ]
        let h = size * 1.4
        NSAttributedString(string: string, attributes: attributes).draw(
            in: NSRect(x: 0, y: y(centerY) - h / 2, width: CGFloat(width), height: h))
    }

    text(heading, size: 20, weight: .semibold, color: ink, centerY: 46)

    // The arrow runs between the two icons, at the height of their centres.
    let from = CGFloat(appX + iconRadius + 22)
    let to = CGFloat(applicationsX - iconRadius - 22)
    let mid = y(appY)
    let shaft = 9.0 as CGFloat
    let headLength = 34.0 as CGFloat
    let headHalf = 28.0 as CGFloat
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: from, y: mid + shaft / 2))
    arrow.line(to: NSPoint(x: to - headLength, y: mid + shaft / 2))
    arrow.line(to: NSPoint(x: to - headLength, y: mid + headHalf))
    arrow.line(to: NSPoint(x: to, y: mid))
    arrow.line(to: NSPoint(x: to - headLength, y: mid - headHalf))
    arrow.line(to: NSPoint(x: to - headLength, y: mid - shaft / 2))
    arrow.line(to: NSPoint(x: from, y: mid - shaft / 2))
    arrow.close()
    arrow.lineJoinStyle = .round
    NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 1).setFill()
    arrow.fill()

    // The First open line sits on a plain pill so it reads on any appearance.
    let pill = NSRect(x: 40, y: y(height - 52) - 19, width: CGFloat(width) - 80, height: 38)
    NSColor(calibratedWhite: 1, alpha: 0.85).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 19, yRadius: 19).fill()
    text(caption, size: 14, weight: .medium, color: ink, centerY: height - 52)

    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: URL(fileURLWithPath: outDir + "/background.png"))
try render(scale: 2).write(to: URL(fileURLWithPath: outDir + "/background@2x.png"))

import AppKit

/// The eyedropper: not one of the tools on the left toolbar but a mode the top toolbar's
/// eyedropper button turns on. While it is on, the next click inside the Capture takes the color
/// of the pixel under the cursor's hot spot as the Annotation color; Esc or another tool ends it.
struct EyedropperTool: EditorTool {
    let id = "eyedropper"
    let order = 0
    let title = "Eyedropper"
    let symbol = "eyedropper"
    var cursor: NSCursor { EyedropperCursor.shared }

    func pointerDown(at point: CGPoint, in session: EditorSession) {
        session.takeColor(at: point)
    }
}

/// The eyedropper's cursor: a pipette drawn as a path (black with a white halo, so it shows on any
/// Capture), with its hot spot at the tip of the pipette: the point whose pixel is sampled. It is
/// drawn, not taken from a symbol, so the tip is exactly where the hot spot says at every scale.
enum EyedropperCursor {
    static let size = NSSize(width: 32, height: 32)
    /// The pipette's tip, in points from the image's bottom left corner.
    private nonisolated static let tip = CGPoint(x: 5, y: 5)

    @MainActor static let shared: NSCursor = {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let path = pipette()
            context.addPath(path)
            context.setLineWidth(2)
            context.setLineJoin(.round)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.strokePath()
            context.addPath(path)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()
            return true
        }
        // A cursor's hot spot is in points from the image's top left corner.
        return NSCursor(image: image, hotSpot: NSPoint(x: tip.x, y: size.height - tip.y))
    }()

    /// A narrow tip widening along a diagonal to a barrel and a round bulb, the tip at `tip`.
    private nonisolated static func pipette() -> CGPath {
        let along = CGVector(dx: 0.7071, dy: 0.7071)
        let across = CGVector(dx: -0.7071, dy: 0.7071)
        func point(_ distance: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(
                x: tip.x + along.dx * distance + across.dx * offset, y: tip.y + along.dy * distance + across.dy * offset)
        }
        let path = CGMutablePath()
        path.move(to: point(0, 0))
        path.addLine(to: point(4, 1.6))
        path.addLine(to: point(13, 3.2))
        path.addLine(to: point(13, -3.2))
        path.addLine(to: point(4, -1.6))
        path.closeSubpath()
        let bulb = point(18, 0)
        path.addEllipse(in: CGRect(x: bulb.x - 5.5, y: bulb.y - 5.5, width: 11, height: 11))
        return path
    }

    /// The visible (more than about 15% opaque) pixel nearest the image's bottom left corner, as a
    /// point (the pixel's centre, origin at the top left), when the image is drawn at `scale` pixels
    /// per point.
    static func tip(of image: NSImage, scale: Int) -> CGPoint? {
        let width = Int(image.size.width) * scale
        let height = Int(image.size.height) * scale
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        // The size first: the context takes its scale (pixels per point) from it.
        rep.size = image.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep), let data = rep.bitmapData else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var best: (distance: Int, x: Int, row: Int)?
        for row in 0..<height {
            for x in 0..<width where data[row * rep.bytesPerRow + x * 4 + 3] > 40 {
                let distance = x + (height - 1 - row)
                if best == nil || distance < best!.distance { best = (distance, x, row) }
            }
        }
        guard let best else { return nil }
        return CGPoint(x: (Double(best.x) + 0.5) / Double(scale), y: (Double(best.row) + 0.5) / Double(scale))
    }
}

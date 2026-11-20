import AppKit
import QuartzCore

/// The loupe tied to the cursor: 15 x 15 device pixels at 8x, nearest neighbour, the pixel under
/// the cursor outlined, and its point and pixel coordinates underneath. A persistent layer tree:
/// a move changes the image layer's `contentsRect` and two strings, nothing is drawn.
@MainActor
final class OverlayLoupe {
    static let cells = 15
    static let zoom: CGFloat = 8
    static let size = CGSize(width: CGFloat(cells) * zoom + 12, height: CGFloat(cells) * zoom + 12 + 6 + 32)

    let layer = CALayer()
    private let image = CALayer()
    private let zone = CALayer()
    private let points: OverlayLabel
    private let pixels: OverlayLabel
    /// The image layer's contents are set once, on the first move, and kept until `releaseFrame`.
    private var hasFrame = false

    init(scale: CGFloat) {
        points = OverlayLabel(scale: scale)
        pixels = OverlayLabel(scale: scale)
        let height = Self.size.height
        let zoneSize = CGFloat(Self.cells) * Self.zoom

        layer.isHidden = true
        layer.bounds = CGRect(origin: .zero, size: Self.size)
        layer.backgroundColor = CGColor(gray: 0.08, alpha: 0.93)
        layer.cornerRadius = 10

        zone.frame = CGRect(x: 6, y: height - 6 - zoneSize, width: zoneSize, height: zoneSize)
        zone.backgroundColor = CGColor(gray: 0.2, alpha: 1)
        zone.masksToBounds = true
        layer.addSublayer(zone)

        image.contentsGravity = .resize
        image.magnificationFilter = .nearest
        image.minificationFilter = .nearest
        image.contentsScale = scale
        zone.addSublayer(image)

        let grid = CAShapeLayer()
        let path = CGMutablePath()
        for step in 1..<Self.cells {
            let offset = CGFloat(step) * Self.zoom
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset, y: zoneSize))
            path.move(to: CGPoint(x: 0, y: offset))
            path.addLine(to: CGPoint(x: zoneSize, y: offset))
        }
        grid.frame = zone.frame
        grid.path = path
        grid.strokeColor = CGColor(gray: 0, alpha: 0.28)
        grid.lineWidth = 1
        grid.fillColor = nil
        layer.addSublayer(grid)

        let middle = CGFloat(Self.cells / 2) * Self.zoom
        let cell = CGPath(rect: CGRect(x: middle, y: middle, width: Self.zoom, height: Self.zoom).insetBy(dx: -0.5, dy: -0.5), transform: nil)
        for (color, width) in [(CGColor(gray: 0, alpha: 1), CGFloat(3)), (CGColor(gray: 1, alpha: 1), CGFloat(1))] {
            let outline = CAShapeLayer()
            outline.frame = zone.frame
            outline.path = cell
            outline.strokeColor = color
            outline.lineWidth = width
            outline.fillColor = nil
            layer.addSublayer(outline)
        }
        layer.addSublayer(points.layer)
        layer.addSublayer(pixels.layer)
    }

    /// Shows the pixels around `cursor` (display-local points, top-left origin), with the loupe's
    /// top-left corner at `origin` inside a scene `sceneHeight` tall.
    func update(frame cgImage: CGImage, scale: Double, cursor: CGPoint, at origin: CGPoint, sceneHeight: CGFloat) {
        layer.isHidden = false
        layer.frame = CGRect(x: origin.x, y: sceneHeight - origin.y - Self.size.height, width: Self.size.width, height: Self.size.height)

        let pixel = AreaGeometry.pixel(of: cursor, scale: scale, width: cgImage.width, height: cgImage.height)
        let half = Self.cells / 2
        let wanted = CGRect(x: pixel.x - half, y: pixel.y - half, width: Self.cells, height: Self.cells)
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let visible = wanted.intersection(imageBounds)
        // Only the part of the 15 x 15 window inside the image is shown; the rest stays grey, so
        // Core Animation never stretches an edge pixel over it.
        if visible.isNull || visible.isEmpty {
            image.isHidden = true
        } else {
            let zoneHeight = CGFloat(Self.cells) * Self.zoom
            let widthPx = CGFloat(cgImage.width), heightPx = CGFloat(cgImage.height)
            let top = (visible.minY - wanted.minY) * Self.zoom
            image.isHidden = false
            image.frame = CGRect(
                x: (visible.minX - wanted.minX) * Self.zoom, y: zoneHeight - top - visible.height * Self.zoom,
                width: visible.width * Self.zoom, height: visible.height * Self.zoom)
            if !hasFrame {
                image.contents = cgImage
                hasFrame = true
            }
            // `contentsRect` measures y from the bottom of the image.
            image.contentsRect = CGRect(
                x: visible.minX / widthPx, y: 1 - visible.maxY / heightPx, width: visible.width / widthPx,
                height: visible.height / heightPx)
        }

        let textTop = 6 + CGFloat(Self.cells) * Self.zoom + 6
        points.set(
            "pt \(Int(cursor.x.rounded(.down))), \(Int(cursor.y.rounded(.down)))", fontSize: 11, color: .white)
        points.place(topLeft: CGPoint(x: 8, y: textTop), parentHeight: Self.size.height)
        pixels.set("px \(pixel.x), \(pixel.y)", fontSize: 11, color: NSColor(white: 0.75, alpha: 1))
        pixels.place(topLeft: CGPoint(x: 8, y: textTop + 15), parentHeight: Self.size.height)
    }

    func hide() { layer.isHidden = true }

    /// Lets go of the frozen frame the image layer reads.
    func releaseFrame() {
        image.contents = nil
        hasFrame = false
    }
}

import AppKit
import QuartzCore

/// The Color picker's loupe: 15 x 15 device pixels at 16x, nearest neighbour, the pixel read
/// outlined in the middle cell, with a swatch of its color and `#RRGGBB` underneath. A persistent
/// layer tree like `OverlayLoupe`: a nudge changes the image layer's `contentsRect`, the swatch's
/// color and two strings, nothing is drawn. The swatch is filled in the frozen frame's own color
/// space, so what it shows is what the hex names.
@MainActor
final class PickLoupe {
    static let cells = 15
    static let zoom: CGFloat = 16
    static let inset: CGFloat = 8
    static let swatchSize: CGFloat = 36
    static let zoneSize = CGFloat(cells) * zoom
    static let size = CGSize(
        width: zoneSize + 2 * inset, height: inset + zoneSize + inset + swatchSize + inset)

    let layer = CALayer()
    private let image = CALayer()
    private let zone = CALayer()
    private let swatch = CALayer()
    private let hex: OverlayLabel
    private let pixels: OverlayLabel
    /// The image layer's contents are set once, on the first update, and kept until `releaseFrame`.
    private var hasFrame = false

    var isShown: Bool { !layer.isHidden }

    init(scale: CGFloat) {
        hex = OverlayLabel(scale: scale)
        pixels = OverlayLabel(scale: scale)
        let height = Self.size.height

        layer.isHidden = true
        layer.bounds = CGRect(origin: .zero, size: Self.size)
        layer.backgroundColor = CGColor(gray: 0.08, alpha: 0.95)
        layer.cornerRadius = 14

        zone.frame = CGRect(x: Self.inset, y: height - Self.inset - Self.zoneSize, width: Self.zoneSize, height: Self.zoneSize)
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
            path.addLine(to: CGPoint(x: offset, y: Self.zoneSize))
            path.move(to: CGPoint(x: 0, y: offset))
            path.addLine(to: CGPoint(x: Self.zoneSize, y: offset))
        }
        grid.frame = zone.frame
        grid.path = path
        grid.strokeColor = CGColor(gray: 0, alpha: 0.28)
        grid.lineWidth = 1
        grid.fillColor = nil
        layer.addSublayer(grid)

        // The outline sits on the pixel read's cell: black under white, so it reads on any color.
        let middle = CGFloat(Self.cells / 2) * Self.zoom
        let cell = CGPath(
            rect: CGRect(x: middle, y: middle, width: Self.zoom, height: Self.zoom).insetBy(dx: -0.5, dy: -0.5),
            transform: nil)
        for (color, width) in [(CGColor(gray: 0, alpha: 1), CGFloat(3)), (CGColor(gray: 1, alpha: 1), CGFloat(1))] {
            let outline = CAShapeLayer()
            outline.frame = zone.frame
            outline.path = cell
            outline.strokeColor = color
            outline.lineWidth = width
            outline.fillColor = nil
            layer.addSublayer(outline)
        }

        swatch.frame = CGRect(x: Self.inset, y: Self.inset, width: Self.swatchSize, height: Self.swatchSize)
        swatch.cornerRadius = 8
        swatch.borderWidth = 1
        swatch.borderColor = CGColor(gray: 1, alpha: 0.7)
        layer.addSublayer(swatch)
        layer.addSublayer(hex.layer)
        layer.addSublayer(pixels.layer)
    }

    /// Where the middle cell's centre is, relative to the loupe's top-left corner (points).
    static let outlinedCentre = CGPoint(
        x: inset + (CGFloat(cells / 2) + 0.5) * zoom, y: inset + (CGFloat(cells / 2) + 0.5) * zoom)

    /// Where the swatch's centre is, relative to the loupe's top-left corner (points).
    static let swatchCentre = CGPoint(x: inset + swatchSize / 2, y: size.height - inset - swatchSize / 2)

    /// Shows the pixels around `pixel` of `cgImage`, the swatch and the hex, with the loupe's top-left
    /// corner at `origin` inside a scene `sceneHeight` tall.
    func update(frame cgImage: CGImage, pixel: PixelPoint, color: PixelColor, at origin: CGPoint, sceneHeight: CGFloat) {
        layer.isHidden = false
        layer.frame = CGRect(
            x: origin.x, y: sceneHeight - origin.y - Self.size.height, width: Self.size.width, height: Self.size.height)

        let half = Self.cells / 2
        let wanted = CGRect(x: pixel.x - half, y: pixel.y - half, width: Self.cells, height: Self.cells)
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        // Only the part of the 15 x 15 window inside the image is shown; the rest stays grey, so
        // Core Animation never stretches an edge pixel over it.
        let visible = wanted.intersection(imageBounds)
        if visible.isNull || visible.isEmpty {
            image.isHidden = true
        } else {
            let widthPx = CGFloat(cgImage.width), heightPx = CGFloat(cgImage.height)
            let top = (visible.minY - wanted.minY) * Self.zoom
            image.isHidden = false
            image.frame = CGRect(
                x: (visible.minX - wanted.minX) * Self.zoom, y: Self.zoneSize - top - visible.height * Self.zoom,
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

        let space = PixelColorReader.rgbSpace(of: cgImage) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        swatch.backgroundColor = CGColor(
            colorSpace: space,
            components: [CGFloat(color.red) / 255, CGFloat(color.green) / 255, CGFloat(color.blue) / 255, 1])

        let textLeft = Self.inset + Self.swatchSize + 10
        let textTop = Self.inset + Self.zoneSize + Self.inset
        hex.set(color.hex, fontSize: 17, weight: .semibold, color: .white)
        hex.place(topLeft: CGPoint(x: textLeft, y: textTop), parentHeight: Self.size.height)
        pixels.set("px \(pixel.x), \(pixel.y)", fontSize: 11, color: NSColor(white: 0.75, alpha: 1))
        pixels.place(topLeft: CGPoint(x: textLeft, y: textTop + 21), parentHeight: Self.size.height)
    }

    func hide() { layer.isHidden = true }

    /// Lets go of the frozen frame the image layer reads.
    func releaseFrame() {
        image.contents = nil
        hasFrame = false
    }
}

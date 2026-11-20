import CoreGraphics

/// The geometry the overlay shares between hit-testing, drawing and the crop. Everything is in
/// points with the origin at the display's top left, except where a pixel is named.
nonisolated enum AreaGeometry {
    /// The rectangle spanned by two corners.
    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// `point` moved inside `bounds` (a point on the far edge counts as outside, as pixels do).
    static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: max(bounds.minX, min(bounds.maxX - 0.001, point.x)),
            y: max(bounds.minY, min(bounds.maxY - 0.001, point.y)))
    }

    /// The device pixel under `point`: the pixel it falls inside, kept inside the image.
    static func pixel(of point: CGPoint, scale: Double, width: Int, height: Int) -> (x: Int, y: Int) {
        (
            x: max(0, min(width - 1, Int((point.x * scale).rounded(.down)))),
            y: max(0, min(height - 1, Int((point.y * scale).rounded(.down))))
        )
    }

    /// The pixel rectangle of an Area given in points: both edges round to the nearest device
    /// pixel (so the size follows the edges, never the other way round), and the result is kept
    /// inside the image. Nil when nothing is left.
    static func pixelRect(of area: CGRect, scale: Double, width: Int, height: Int) -> PixelRect? {
        let left = max(0, Int((area.minX * scale).rounded()))
        let top = max(0, Int((area.minY * scale).rounded()))
        let right = min(width, Int((area.maxX * scale).rounded()))
        let bottom = min(height, Int((area.maxY * scale).rounded()))
        guard right > left, bottom > top else { return nil }
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The Area an overlay Area snaps to: the pixel rectangle back in points, which is what
    /// the overlay draws and what the Capture holds.
    static func points(of pixels: PixelRect, scale: Double) -> CGRect {
        CGRect(
            x: Double(pixels.x) / scale, y: Double(pixels.y) / scale,
            width: Double(pixels.width) / scale, height: Double(pixels.height) / scale)
    }
}

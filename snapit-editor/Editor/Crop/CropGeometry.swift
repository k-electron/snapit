import CoreGraphics

/// Which part of the crop rectangle a handle drags.
nonisolated enum CropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// Where the handle sits on `rect`.
    func position(on rect: CGRect) -> CGPoint {
        CGPoint(
            x: movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX,
            y: movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY)
    }
}

/// The arithmetic of cropping, with no view and no state: where handles are, how a drag changes
/// the rectangle, and how a rectangle in image points becomes whole device pixels. The canvas,
/// the Apply action and the Export's crop stage share `pixelRect`, so they agree on every pixel.
nonisolated enum CropGeometry {
    /// The smallest crop, in image points each way.
    static let minimumSize: CGFloat = 8

    /// The device pixels a rectangle of image points covers: each edge snaps to the nearest
    /// pixel (a fractional point crop never keeps half a pixel) and the result lies inside the
    /// image. Nil when nothing is left.
    static func pixelRect(_ rect: CGRect, scale: Double, width: Int, height: Int) -> PixelRect? {
        func snap(_ value: CGFloat, limit: Int) -> Int { min(max(Int((value * scale).rounded()), 0), limit) }
        let x0 = snap(rect.minX, limit: width), x1 = snap(rect.maxX, limit: width)
        let y0 = snap(rect.minY, limit: height), y1 = snap(rect.maxY, limit: height)
        guard x1 > x0, y1 > y0 else { return nil }
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The image points a pixel rectangle covers.
    static func points(_ rect: PixelRect, scale: Double) -> CGRect {
        CGRect(
            x: Double(rect.x) / scale, y: Double(rect.y) / scale, width: Double(rect.width) / scale,
            height: Double(rect.height) / scale)
    }

    /// The handle within `reach` of `point`, the nearest one.
    static func handle(at point: CGPoint, in rect: CGRect, reach: CGFloat) -> CropHandle? {
        CropHandle.allCases
            .map { ($0, hypot($0.position(on: rect).x - point.x, $0.position(on: rect).y - point.y)) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?.0
    }

    /// The rectangle spanned by two points, inside `bounds`.
    static func spanned(from anchor: CGPoint, to point: CGPoint, in bounds: CGRect) -> CGRect {
        let a = clamp(anchor, to: bounds), b = clamp(point, to: bounds)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// `rect` moved by `delta`, kept inside `bounds`.
    static func moved(_ rect: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.width, dy: delta.height)
        moved.origin.x = min(max(moved.origin.x, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.origin.y, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// `rect` with the edges `handle` drags moved to `point`, inside `bounds` and never closer to
    /// the opposite edge than `minimumSize`.
    static func resized(_ rect: CGRect, handle: CropHandle, to point: CGPoint, in bounds: CGRect) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesLeft { minX = min(max(point.x, bounds.minX), maxX - minimumSize) }
        if handle.movesRight { maxX = max(min(point.x, bounds.maxX), minX + minimumSize) }
        if handle.movesTop { minY = min(max(point.y, bounds.minY), maxY - minimumSize) }
        if handle.movesBottom { maxY = max(min(point.y, bounds.maxY), minY + minimumSize) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}

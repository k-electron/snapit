import CoreGraphics

/// Where the Action bar goes: below the Area, else above it, else inside it at the bottom.
/// Horizontally it is centred on the Area and kept inside the display, so it is on screen at
/// every edge and corner. Points, origin at the display's top left.
nonisolated enum ActionBarPlacement {
    /// The space kept between the bar and the Area, and between the bar and the display's edge.
    static let gap: CGFloat = 10
    static let margin: CGFloat = 8

    static func frame(size: CGSize, area: CGRect, in bounds: CGRect) -> CGRect {
        let minY = bounds.minY + margin
        let maxY = bounds.maxY - margin - size.height
        var y = area.maxY + gap
        if y > maxY { y = area.minY - gap - size.height }
        if y < minY { y = area.maxY - gap - size.height }
        y = max(minY, min(maxY, y))
        // A bar wider than the display (less its margins) is centred on it, overflowing both
        // sides equally rather than only the right.
        let minX = bounds.minX + margin
        let maxX = bounds.maxX - margin - size.width
        let x = minX <= maxX ? max(minX, min(maxX, area.midX - size.width / 2)) : bounds.midX - size.width / 2
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

import CoreGraphics

/// Where the Action bar goes: below the selection, else above it, else inside it at the bottom.
/// Horizontally it is centred on the selection and kept inside the display, so it is on screen at
/// every edge and corner. Points, origin at the display's top left.
nonisolated enum ActionBarPlacement {
    /// The space kept between the bar and the selection, and between the bar and the display's edge.
    static let gap: CGFloat = 10
    static let margin: CGFloat = 8

    static func frame(size: CGSize, selection: CGRect, in bounds: CGRect) -> CGRect {
        let minY = bounds.minY + margin
        let maxY = bounds.maxY - margin - size.height
        var y = selection.maxY + gap
        if y > maxY { y = selection.minY - gap - size.height }
        if y < minY { y = selection.maxY - gap - size.height }
        y = max(minY, min(maxY, y))
        let maxX = bounds.maxX - margin - size.width
        let x = max(bounds.minX + margin, min(maxX, selection.midX - size.width / 2))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

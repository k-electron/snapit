import CoreGraphics

/// Where the countdown badge goes: outside the Area (and its border), below it and aligned to its
/// right edge; above it when there is no room below; inside its top-right corner as a last resort.
/// Points, origin at the display's top left.
nonisolated enum TimedBadgePlacement {
    static let size = CGSize(width: 84, height: 30)
    /// The space between the border and the badge.
    static let gap: CGFloat = 6

    /// `border` is the Area with its border, `bounds` the display, `topInset` the menu bar's height.
    static func frame(border: CGRect, in bounds: CGRect, topInset: CGFloat) -> CGRect {
        var origin = CGPoint(x: border.maxX - size.width, y: border.maxY + gap)
        if origin.y + size.height > bounds.maxY - 4 { origin.y = border.minY - gap - size.height }
        if origin.y < bounds.minY + topInset + 4 {
            origin = CGPoint(
                x: border.maxX - size.width - 8, y: max(border.minY, bounds.minY + topInset) + 8)
        }
        origin.x = max(bounds.minX + 4, min(origin.x, bounds.maxX - size.width - 4))
        return CGRect(origin: origin, size: size)
    }
}

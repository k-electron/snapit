import AppKit

/// One of the eight handles of an adjusted Area, and the geometry that goes with them:
/// which handle a point grabs, what resizing and moving do to the Area. Points, origin at the
/// display's top left.
nonisolated enum AreaHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// How far from a handle's centre it can be grabbed.
    static let reach: CGFloat = 8
    /// How far from an edge (outside or inside) the whole edge can be grabbed.
    static let band: CGFloat = 6

    func center(of area: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: area.minX, y: area.minY)
        case .top: CGPoint(x: area.midX, y: area.minY)
        case .topRight: CGPoint(x: area.maxX, y: area.minY)
        case .right: CGPoint(x: area.maxX, y: area.midY)
        case .bottomRight: CGPoint(x: area.maxX, y: area.maxY)
        case .bottom: CGPoint(x: area.midX, y: area.maxY)
        case .bottomLeft: CGPoint(x: area.minX, y: area.maxY)
        case .left: CGPoint(x: area.minX, y: area.midY)
        }
    }

    /// The handle `point` grabs: the nearest one within reach of its centre, else the edge whose
    /// band the point is in. Nil inside the Area or away from it.
    static func hit(_ area: CGRect, at point: CGPoint) -> AreaHandle? {
        let near =
            allCases
            .map { ($0, hypot($0.center(of: area).x - point.x, $0.center(of: area).y - point.y)) }
            .filter { handle, _ in
                let center = handle.center(of: area)
                return abs(center.x - point.x) <= reach && abs(center.y - point.y) <= reach
            }
            .min { $0.1 < $1.1 }
        if let near { return near.0 }

        // The bands shrink with a small Area so that its inside can still be grabbed to move it.
        let band = min(band, min(area.width, area.height) / 3)
        let withinX = point.x >= area.minX - band && point.x <= area.maxX + band
        let withinY = point.y >= area.minY - band && point.y <= area.maxY + band
        var best: (AreaHandle, CGFloat)?
        func consider(_ handle: AreaHandle, _ distance: CGFloat, _ applies: Bool) {
            guard applies, distance <= band, best == nil || distance < best!.1 else { return }
            best = (handle, distance)
        }
        consider(.top, abs(point.y - area.minY), withinX)
        consider(.bottom, abs(point.y - area.maxY), withinX)
        consider(.left, abs(point.x - area.minX), withinY)
        consider(.right, abs(point.x - area.maxX), withinY)
        return best?.0
    }

    /// `area` with this handle moved by `delta`. The other edges stay where they were, so a handle
    /// dragged past the opposite edge turns the Area over. The result stays inside `bounds` and is
    /// at least a point wide and high.
    func resized(_ area: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        var left = area.minX, top = area.minY, right = area.maxX, bottom = area.maxY
        switch self {
        case .topLeft: left += delta.width; top += delta.height
        case .top: top += delta.height
        case .topRight: right += delta.width; top += delta.height
        case .right: right += delta.width
        case .bottomRight: right += delta.width; bottom += delta.height
        case .bottom: bottom += delta.height
        case .bottomLeft: left += delta.width; bottom += delta.height
        case .left: left += delta.width
        }
        func inside(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat { max(range.lowerBound, min(range.upperBound, value)) }
        let xs = bounds.minX...bounds.maxX, ys = bounds.minY...bounds.maxY
        var result = AreaGeometry.rect(
            CGPoint(x: inside(left, xs), y: inside(top, ys)), CGPoint(x: inside(right, xs), y: inside(bottom, ys)))
        if result.width < 1 {
            result.size.width = 1
            result.origin.x = min(result.origin.x, bounds.maxX - 1)
        }
        if result.height < 1 {
            result.size.height = 1
            result.origin.y = min(result.origin.y, bounds.maxY - 1)
        }
        return result
    }

    /// `area` moved by `delta`, kept inside `bounds`.
    static func moved(_ area: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        let dx = max(bounds.minX - area.minX, min(delta.width, bounds.maxX - area.maxX))
        let dy = max(bounds.minY - area.minY, min(delta.height, bounds.maxY - area.maxY))
        return area.offsetBy(dx: dx, dy: dy)
    }

    /// The cursor over this handle.
    var cursor: NSCursor {
        let position: NSCursor.FrameResizePosition =
            switch self {
            case .topLeft: .topLeft
            case .top: .top
            case .topRight: .topRight
            case .right: .right
            case .bottomRight: .bottomRight
            case .bottom: .bottom
            case .bottomLeft: .bottomLeft
            case .left: .left
            }
        return NSCursor.frameResize(position: position, directions: .all)
    }
}

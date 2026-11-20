import CoreGraphics

nonisolated extension AnnotationKindID {
    static let arrow = AnnotationKindID("arrow")
}

/// Arrow: a shaft from `start` to a filled triangular head at `end`, in one color.
nonisolated struct ArrowAnnotationKind: AnnotationKind {
    let id = AnnotationKindID.arrow

    func paint(for annotation: Annotation) -> AnnotationPaint {
        let color = annotation.style.color.cgColor
        return AnnotationPaint(
            path: Self.path(from: annotation.start, to: annotation.end, width: annotation.style.width),
            fill: color, stroke: color, lineWidth: annotation.style.width, lineCap: .round, lineJoin: .round)
    }

    func handles(of annotation: Annotation) -> [CGPoint] { [annotation.start, annotation.end] }

    func isLargeEnough(_ annotation: Annotation) -> Bool {
        hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y) >= AnnotationLimits.smallestSize
    }

    func moveHandle(_ index: Int, to point: CGPoint, in annotation: Annotation) -> Annotation {
        var copy = annotation
        if index == 0 { copy.start = point } else if index == 1 { copy.end = point }
        return copy
    }

    /// The shaft and the head's triangle. The head grows with the width.
    static func path(from tail: CGPoint, to tip: CGPoint, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let length = hypot(tip.x - tail.x, tip.y - tail.y)
        guard length > 0.5 else { return path }
        let ux = (tip.x - tail.x) / length
        let uy = (tip.y - tail.y) / length
        let headLength = min(length * 0.7, 10 + 3 * width)
        let headHalfWidth = headLength * 0.5
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        path.move(to: tail)
        path.addLine(to: base)
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x - uy * headHalfWidth, y: base.y + ux * headHalfWidth))
        path.addLine(to: CGPoint(x: base.x + uy * headHalfWidth, y: base.y - ux * headHalfWidth))
        path.closeSubpath()
        return path
    }
}

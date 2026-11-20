import CoreGraphics

nonisolated extension AnnotationKindID {
    static let highlighter = AnnotationKindID("highlighter")
}

/// Highlighter: a translucent marker stroke from `start` to `end`, as thick as its width, with
/// square ends. The stored color is opaque; the translucency is applied where it is painted, so
/// the canvas and the Export blend it the same way (plain alpha over the Capture).
nonisolated struct HighlighterAnnotationKind: AnnotationKind {
    let id = AnnotationKindID.highlighter
    let widthChoice = WidthChoice.highlighter

    /// How much of the Capture still shows through, as the share of the color laid over it.
    static let opacity: CGFloat = 0.4

    func paint(for annotation: Annotation) -> AnnotationPaint {
        let path = CGMutablePath()
        path.move(to: annotation.start)
        path.addLine(to: annotation.end)
        return AnnotationPaint(
            path: path, stroke: annotation.style.color.cgColor.copy(alpha: Self.opacity),
            lineWidth: annotation.style.width, lineCap: .butt)
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
}

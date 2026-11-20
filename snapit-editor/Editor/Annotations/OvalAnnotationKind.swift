import CoreGraphics

nonisolated extension AnnotationKindID {
    static let oval = AnnotationKindID("oval")
}

/// Oval: an outline, or a solid fill, of the ellipse in the box from `start` to `end`. A click
/// in a corner of that box, outside the ellipse, is not on it.
nonisolated struct OvalAnnotationKind: AnnotationKind {
    let id = AnnotationKindID.oval
    let supportsFill = true

    func paint(for annotation: Annotation) -> AnnotationPaint {
        let color = annotation.style.color.cgColor
        let path = CGPath(ellipseIn: annotation.box, transform: nil)
        if annotation.style.filled { return AnnotationPaint(path: path, fill: color) }
        return AnnotationPaint(path: path, stroke: color, lineWidth: annotation.style.width, lineJoin: .round)
    }
}

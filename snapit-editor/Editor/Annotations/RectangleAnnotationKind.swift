import CoreGraphics

nonisolated extension AnnotationKindID {
    static let rectangle = AnnotationKindID("rectangle")
}

/// Rectangle: an outline, or a solid fill, spanning the box from `start` to `end`.
nonisolated struct RectangleAnnotationKind: AnnotationKind {
    let id = AnnotationKindID.rectangle
    let supportsFill = true

    func paint(for annotation: Annotation) -> AnnotationPaint {
        let color = annotation.style.color.cgColor
        let path = CGPath(rect: annotation.box, transform: nil)
        if annotation.style.filled { return AnnotationPaint(path: path, fill: color) }
        return AnnotationPaint(path: path, stroke: color, lineWidth: annotation.style.width, lineJoin: .miter)
    }
}

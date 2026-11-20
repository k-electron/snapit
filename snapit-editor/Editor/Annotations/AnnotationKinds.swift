/// Every kind of Annotation. A feature adds its kind to `all` with one line (a line each, with
/// a trailing comma, so two additions are a one-line merge conflict that keeps both sides).
nonisolated enum AnnotationKinds {
    static let all: [any AnnotationKind] = [
        ArrowAnnotationKind(),
        RectangleAnnotationKind(),
        OvalAnnotationKind(),
    ]

    /// Kinds the scripted run adds (`EditorToolTestCommands`), to exercise what no kind in `all`
    /// does yet (a kind drawn beneath the Annotations). Empty outside test mode.
    nonisolated(unsafe) static var testKinds: [any AnnotationKind] = []

    /// What the kind named `id` does; nil for a name no kind here has (an Annotation a newer
    /// snapit wrote), which is kept in the document but never drawn or picked.
    static func kind(_ id: AnnotationKindID) -> (any AnnotationKind)? {
        all.first { $0.id == id } ?? testKinds.first { $0.id == id }
    }

    /// The Annotations in the order they are painted, which Export and the canvas share: first the
    /// kinds another stage draws (`drawnByAnnotationStage` false: Redaction pixelates before any
    /// Annotation is drawn, so it lies beneath them all), then the rest, each in document order.
    /// A name no kind here has is left out. Hit testing walks it from the end.
    static func paintOrder(_ annotations: [Annotation]) -> [Annotation] {
        let known = annotations.compactMap { annotation in kind(annotation.kind).map { (annotation, $0) } }
        let beneath = known.filter { !$0.1.drawnByAnnotationStage }.map { $0.0 }
        let above = known.filter { $0.1.drawnByAnnotationStage }.map { $0.0 }
        return beneath + above
    }
}

/// Every kind of Annotation. A feature adds its kind to `all` with one line (a line each, with
/// a trailing comma, so two additions are a one-line merge conflict that keeps both sides).
nonisolated enum AnnotationKinds {
    static let all: [any AnnotationKind] = [
        ArrowAnnotationKind(),
        RectangleAnnotationKind(),
        OvalAnnotationKind(),
    ]

    /// What the kind named `id` does; nil for a name no kind here has (an Annotation a newer
    /// snapit wrote), which is kept in the document but never drawn or picked.
    static func kind(_ id: AnnotationKindID) -> (any AnnotationKind)? {
        all.first { $0.id == id }
    }
}

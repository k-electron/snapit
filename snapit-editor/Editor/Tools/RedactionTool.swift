/// Redaction: drag across what to hide. It is pixelated in bold blocks on the canvas and, on
/// Export, the pixels beneath it are destroyed.
struct RedactionTool: AnnotationDrawingTool {
    let id = "redaction"
    let order = 700
    let title = "Redaction"
    let symbol = "squareshape.split.3x3"
    let key: Character? = "x"
    let annotationKind: AnnotationKindID? = .redaction
}

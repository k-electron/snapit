/// Oval: drag across the box the oval fills. An outline or a solid fill.
struct OvalTool: AnnotationDrawingTool {
    let id = "oval"
    let order = 400
    let title = "Oval"
    let symbol = "oval"
    let key: Character? = "o"
    let annotationKind: AnnotationKindID? = .oval
}

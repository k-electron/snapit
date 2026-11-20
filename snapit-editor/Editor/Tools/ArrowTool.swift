/// Arrow: drag from the tail to the tip.
struct ArrowTool: AnnotationDrawingTool {
    let id = "arrow"
    let order = 200
    let title = "Arrow"
    let symbol = "arrow.up.right"
    let key: Character? = "a"
    let annotationKind: AnnotationKindID? = .arrow
}

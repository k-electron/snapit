/// Rectangle: drag from one corner to the opposite one. An outline or a solid fill.
struct RectangleTool: AnnotationDrawingTool {
    let id = "rectangle"
    let order = 300
    let title = "Rectangle"
    let symbol = "rectangle"
    let key: Character? = "r"
    let annotationKind: AnnotationKindID? = .rectangle
}

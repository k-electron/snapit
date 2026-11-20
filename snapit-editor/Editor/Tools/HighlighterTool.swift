/// Highlighter: drag along what to mark; a translucent stroke, as thick as the Highlighter width.
struct HighlighterTool: AnnotationDrawingTool {
    let id = "highlighter"
    let order = 600
    let title = "Highlighter"
    let symbol = "highlighter"
    let key: Character? = "h"
    let annotationKind: AnnotationKindID? = .highlighter
}

import CoreGraphics

/// A tool that drags out one kind of Annotation: press where it starts, drag, release where it
/// ends. It has only to name its `annotationKind`; the drag, the minimum size and the single Undo
/// step are `EditorSession`'s. (Tools with their own gestures, like Text, conform to `EditorTool`
/// directly.)
@MainActor
protocol AnnotationDrawingTool: EditorTool {}

extension AnnotationDrawingTool {
    func pointerDown(at point: CGPoint, in session: EditorSession) {
        guard let kind = annotationKind else { return }
        session.beginDrawing(kind, at: point)
    }

    func pointerDragged(to point: CGPoint, in session: EditorSession) {
        session.continueDrawing(to: point)
    }

    func pointerUp(at point: CGPoint, in session: EditorSession) {
        session.finishDrawing(at: point)
    }
}

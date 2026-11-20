import AppKit

/// Select: picks the Annotation under the pointer by its exact shape, moves it by dragging it
/// and resizes it by dragging a handle. A click on empty canvas selects nothing.
struct SelectTool: EditorTool {
    let id = "select"
    let order = 100
    let title = "Select"
    let symbol = "cursorarrow"
    let key: Character? = "v"
    let cursor = NSCursor.arrow

    func pointerDown(at point: CGPoint, in session: EditorSession) {
        session.beginSelecting(at: point)
    }

    func pointerDragged(to point: CGPoint, in session: EditorSession) {
        session.continueSelecting(to: point)
    }

    func pointerUp(at point: CGPoint, in session: EditorSession) {
        session.continueSelecting(to: point)
        session.finishSelecting()
    }
}

import AppKit

/// Text: click where the text starts, type, then click away (or press Esc) to finish it. A click
/// on a Text edits it. The typing itself is the text view's; see `EditorSession+Text.swift`.
struct TextTool: EditorTool {
    let id = "text"
    let order = 500
    let title = "Text"
    let symbol = "textformat"
    let key: Character? = "t"
    let annotationKind: AnnotationKindID? = .text
    let cursor = NSCursor.iBeam

    func pointerDown(at point: CGPoint, in session: EditorSession) {
        session.beginText(at: point)
    }
}

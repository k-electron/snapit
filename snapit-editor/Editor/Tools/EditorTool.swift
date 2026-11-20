import AppKit
import CoreGraphics

/// One Annotation tool on the Editor's left toolbar. A feature adds a file with its tool and
/// one line in `ToolRegistry`.
///
/// The canvas forwards the pointer to the active tool in image points (the Capture's own
/// coordinates, origin at the top left), so a tool never deals with zoom or the view's
/// coordinates. A tool draws by adding and updating Core Animation layers on the canvas
/// (`CanvasView.contentLayer`), never by asking a view to redraw.
@MainActor
protocol EditorTool {
    /// Stable name.
    var id: String { get }
    /// Position on the toolbar, lowest first.
    var order: Int { get }
    /// What the tool is called in its tooltip.
    var title: String { get }
    /// SF Symbol name.
    var symbol: String { get }
    /// The key that picks the tool; nil for none.
    var key: Character? { get }
    /// The kind of Annotation the tool draws; nil for a tool that does not draw one (Select).
    var annotationKind: AnnotationKindID? { get }
    /// The cursor over the canvas while the tool is active.
    var cursor: NSCursor { get }

    func pointerDown(at point: CGPoint, in session: EditorSession)
    func pointerDragged(to point: CGPoint, in session: EditorSession)
    func pointerUp(at point: CGPoint, in session: EditorSession)
}

extension EditorTool {
    var key: Character? { nil }
    var annotationKind: AnnotationKindID? { nil }
    var cursor: NSCursor { .crosshair }
    /// The hover tooltip: the name and its key.
    var tooltip: String { key.map { "\(title) (\($0.uppercased()))" } ?? title }

    func pointerDown(at point: CGPoint, in session: EditorSession) {}
    func pointerDragged(to point: CGPoint, in session: EditorSession) {}
    func pointerUp(at point: CGPoint, in session: EditorSession) {}
}

import AppKit

/// Connects the color panel to the Editor whose color wheel button opened it. The panel is
/// continuous: it reports every step of a drag, so a drag is one Undo step. The first change of a
/// drag opens an Undo bracket on the document; the mouse button coming up closes it (an event
/// monitor that exists only while a drag is open, so nothing runs at rest). A change with the
/// button up (a typed value) is a step of its own.
@MainActor
final class ColorPanelController: NSObject {
    static let shared = ColorPanelController()

    private weak var session: EditorSession?
    private weak var bracketedDocument: EditorDocument?
    private var mouseUpMonitor: Any?

    private var panel: any ColorPanelEdge { ColorPanelEdges.current }

    /// Shows the panel for this Editor, starting at its current Annotation color.
    func open(for session: EditorSession) {
        endGesture()
        self.session = session
        panel.present(color: NSColor(cgColor: session.shownColor.cgColor) ?? .red, target: self, action: #selector(panelChanged(_:)))
    }

    /// Takes the panel away when the Editor it serves closes, so it never keeps the helper alive.
    func sessionClosed(_ closing: EditorSession) {
        guard session === closing else { return }
        endGesture()
        panel.dismiss()
        session = nil
    }

    @objc private func panelChanged(_ sender: Any?) {
        guard let session, let color = panel.color.usingColorSpace(.sRGB) else { return }
        let chosen = AnnotationColor(
            red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
        if panel.isDragging {
            if bracketedDocument == nil, let document = session.document {
                document.edit { $0.begin() }
                bracketedDocument = document
                mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                    self?.endGesture()
                    return event
                }
            }
        } else {
            endGesture()
        }
        session.setAnnotationColor(chosen)
    }

    /// Ends the open drag as one Undo step. Anything else that edits or undoes calls this first, so
    /// a bracket never stays open under it.
    func endGesture() {
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
        mouseUpMonitor = nil
        guard let document = bracketedDocument else { return }
        bracketedDocument = nil
        document.edit { $0.end() }
    }
}

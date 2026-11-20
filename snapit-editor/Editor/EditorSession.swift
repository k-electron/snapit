import AppKit
import Observation

/// One Editor: its window and everything the user does in it. Actions that a button, a key and
/// a test command all trigger live here once, in `EditorSession+…` files (Copy is
/// `EditorSession+Copy.swift`).
///
/// A session is built without a Capture: the window, the toolbars and the canvas layers exist
/// from `init`, hidden. A helper warming up builds one ahead of time; `attach(_:)` gives it the
/// Capture and `show()` puts it on screen.
@MainActor
@Observable
final class EditorSession: NSObject, NSWindowDelegate {
    /// The Capture being edited; nil until `attach(_:)`.
    private(set) var document: EditorDocument?
    /// The id of the active tool in `ToolRegistry`.
    private(set) var selectedToolID = ToolRegistry.initial.id
    /// The Annotation Select has picked, or the one just drawn (see `EditorSession+Annotations`).
    var selectedAnnotationID: Int?
    /// The style a new Annotation starts with: the color, width and fill used last, which
    /// `AnnotationSettings` remembers across launches.
    var annotationStyle = AnnotationSettings.style
    /// The thickness a new Highlighter gets (it is remembered apart from the line width).
    var highlighterWidth = AnnotationSettings.highlighterWidth
    /// True while the eyedropper waits for a click inside the Capture (see `EditorSession+Color`).
    var isPickingColor = false
    /// What the toolbar shows about the Annotations. Changes when a gesture starts or ends, a
    /// selection changes or Undo history changes, never while the pointer moves, so the toolbar
    /// pills are not rebuilt on every mouse move.
    var toolbarState = AnnotationToolbarState()
    /// The move, resize or drawing the pointer is in the middle of.
    @ObservationIgnored var annotationGesture: AnnotationGesture? {
        didSet { refreshToolbarState() }
    }
    /// True while Copy (or any Export) is running.
    var isExporting = false
    /// True when this session was built ahead of its Capture (a warm-up).
    @ObservationIgnored var wasWarmedUp = false
    /// The running Copy or Save, so a caller can wait for it.
    @ObservationIgnored var copyTask: Task<Void, Never>?

    @ObservationIgnored private(set) var chrome: EditorChrome?
    @ObservationIgnored var onClosed: ((EditorSession) -> Void)?
    @ObservationIgnored private var isClosing = false

    override init() {
        super.init()
        let chrome = EditorChrome(session: self)
        chrome.window.delegate = self
        self.chrome = chrome
    }

    var window: EditorWindow? { chrome?.window }
    var canvas: CanvasView? { chrome?.canvas }

    /// The tool the pointer drives: the eyedropper while it is picking, else the selected tool.
    var currentTool: any EditorTool {
        isPickingColor ? EyedropperTool() : (ToolRegistry.tool(id: selectedToolID) ?? ToolRegistry.initial)
    }

    func selectTool(id: String) {
        guard ToolRegistry.tool(id: id) != nil else { return }
        commitTextEditing()
        cancelPickingColor()
        endColorGesture()
        abortAnnotationGesture()
        selectedToolID = id
        // A drawing tool starts from nothing selected: its options (the fill) are then the
        // tool's, not the previous selection's.
        if ToolRegistry.tool(id: id)?.annotationKind != nil, selectedAnnotationID != nil { selectAnnotation(nil) }
        refreshToolbarState()
        canvas.map { $0.window?.invalidateCursorRects(for: $0) }
    }

    // MARK: Window

    /// Gives the Editor its Capture and sizes the window to it.
    func attach(_ document: EditorDocument) {
        self.document = document
        // A warmed-up Editor was built before the last style was chosen.
        annotationStyle = AnnotationSettings.style
        highlighterWidth = AnnotationSettings.highlighterWidth
        chrome?.attach(document)
        document.onChange = { [weak self] in self?.annotationsDidChange() }
        annotationsDidChange()
    }

    /// Puts the window on screen. The helper is already a regular app by now.
    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Brings an open Editor in front of every other window and makes it key.
    func bringForward() {
        window?.makeKeyAndOrderFront(nil)
        HelperLifecycle.activate()
    }

    /// Closes the Editor. Nothing is asked and nothing is exported.
    func close() {
        guard !isClosing else { return }
        window?.close()
    }

    /// Frees a session that never showed (a warm-up that was cancelled).
    func discard() {
        guard !isClosing else { return }
        isClosing = true
        ColorPanelController.shared.sessionClosed(self)
        chrome?.tearDown()
        chrome = nil
    }

    /// Esc: closes the Editor without exporting. A tool with something pending (text being
    /// typed, a crop) finishes that first, before this closes.
    func escape() {
        if commitTextEditing() || cancelPickingColor() { return }
        close()
    }

    /// Delete Capture: closes the Editor at once and has the menu bar app remove the Capture file.
    func deleteCapture() {
        guard let number = document?.captureNumber else { return close() }
        // The helper may quit as this window closes, so the menu bar app hears first; the
        // main thread never waits for the reply.
        Task {
            _ = try? await CommandSocketClient.send(
                .deleteCapture, arguments: [String(number)], to: AppIdentity.appSocketPath)
            close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        commitTextEditing(refocus: false)
        ColorPanelController.shared.sessionClosed(self)
        isClosing = true
        if let number = document?.captureNumber { SaveFailureSignal.forget(captureNumber: number) }
        onClosed?(self)
        // A button's own action may be what closed the window: free everything one run-loop
        // turn later, once that action has returned.
        DispatchQueue.main.async { [self] in
            chrome?.tearDown()
            chrome = nil
        }
    }
}

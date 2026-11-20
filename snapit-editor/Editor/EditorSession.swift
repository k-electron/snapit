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
    /// What the toolbar shows about the Annotations. Changes when a gesture starts or ends, a
    /// selection changes or Undo history changes, never while the pointer moves, so the toolbar
    /// pills are not rebuilt on every mouse move.
    var toolbarState = AnnotationToolbarState()
    /// The move, resize or drawing the pointer is in the middle of.
    @ObservationIgnored var annotationGesture: AnnotationGesture? {
        didSet {
            refreshToolbarState()
            if annotationGesture == nil { canvas?.settlePreviews() }
        }
    }
    /// The Crop tool's rectangle and drag (`EditorSession+Crop.swift`).
    @ObservationIgnored var cropState = CropState()
    /// True while Copy (or any Export) is running.
    var isExporting = false
    /// True when this session was built ahead of its Capture (a warm-up).
    @ObservationIgnored var wasWarmedUp = false
    /// The running Copy or Save, so a caller can wait for it.
    @ObservationIgnored var copyTask: Task<Void, Never>?

    /// Set while this is the Last Capture's Editor: it keeps the state file current.
    @ObservationIgnored var lastCapture: LastCapturePersistence?
    @ObservationIgnored private(set) var chrome: EditorChrome?
    @ObservationIgnored var onClosed: ((EditorSession) -> Void)?
    @ObservationIgnored private(set) var isClosing = false

    override init() {
        super.init()
        let chrome = EditorChrome(session: self)
        chrome.window.delegate = self
        self.chrome = chrome
    }

    var window: EditorWindow? { chrome?.window }
    var canvas: CanvasView? { chrome?.canvas }

    var currentTool: any EditorTool { ToolRegistry.tool(id: selectedToolID) ?? ToolRegistry.initial }

    func selectTool(id: String) {
        guard ToolRegistry.tool(id: id) != nil else { return }
        abortAnnotationGesture()
        let previousToolID = selectedToolID
        selectedToolID = id
        cropToolChanged(from: previousToolID, to: id)
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
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        HelperLifecycle.activate()
    }

    /// Closes the Editor. Nothing is asked and nothing is exported. What the user asks for (the
    /// close button, ⌘W, Esc) is `requestClose()`; Delete Capture, Copy and Save close this way.
    func close() {
        guard !isClosing else { return }
        window?.close()
    }

    /// Frees a session that never showed (a warm-up that was cancelled).
    func discard() {
        guard !isClosing else { return }
        isClosing = true
        chrome?.tearDown()
        chrome = nil
    }

    /// Esc: closes the Editor without exporting, asking first when `closeWouldLoseWork`. A tool
    /// with something pending (text being typed, a crop) finishes that first, before this closes.
    func escape() {
        if cancelCropIfCropping() { return }
        requestClose()
    }

    /// Delete Capture: closes the Editor at once and has the menu bar app remove the Capture file.
    func deleteCapture() {
        guard let number = document?.captureNumber else { return close() }
        // The helper may quit as this window closes, so the menu bar app hears first; the
        // main thread never waits for the reply.
        EditorSessions.shared.markDeleted(captureNumber: number)
        Task {
            // The Capture's state is not written again (not even by the close below), and a write
            // already queued has run or been dropped before the files are removed.
            if isLastCapture {
                stopBeingLastCapture()
                LastCaptureStore.shared.supersede()
                await LastCaptureStore.shared.fence()
            }
            _ = try? await CommandSocketClient.send(
                .deleteCapture, arguments: [String(number)], to: AppIdentity.appSocketPath)
            close()
        }
    }

    /// The close button: asks first when the Editor holds unexported edits.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        EditorPrompts.shared.dismiss(for: self)
        isClosing = true
        if let number = document?.captureNumber { SaveFailureSignal.forget(captureNumber: number) }
        saveLastCaptureOnClose()
        onClosed?(self)
        // A button's own action may be what closed the window: free everything one run-loop
        // turn later, once that action has returned.
        DispatchQueue.main.async { [self] in
            chrome?.tearDown()
            chrome = nil
        }
    }
}

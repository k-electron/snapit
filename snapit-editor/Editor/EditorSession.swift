import AppKit
import Observation

/// One open Editor: its document, its window and everything the user does in it. Actions that
/// a button, a key and a test command all trigger live here once, in `EditorSession+…` files
/// (Copy is `EditorSession+Copy.swift`).
@MainActor
@Observable
final class EditorSession: NSObject, NSWindowDelegate {
    let document: EditorDocument
    /// The id of the active tool in `ToolRegistry`.
    private(set) var selectedToolID = ToolRegistry.initial.id
    /// True while Copy (or any Export) is running.
    var isExporting = false
    /// The running Copy, so a caller can wait for it.
    @ObservationIgnored var copyTask: Task<Void, Never>?

    @ObservationIgnored private(set) var chrome: EditorChrome?
    @ObservationIgnored var onClosed: ((EditorSession) -> Void)?
    @ObservationIgnored private var isClosing = false

    init(document: EditorDocument) {
        self.document = document
        super.init()
    }

    var window: EditorWindow? { chrome?.window }
    var canvas: CanvasView? { chrome?.canvas }

    var currentTool: any EditorTool { ToolRegistry.tool(id: selectedToolID) ?? ToolRegistry.initial }

    func selectTool(id: String) {
        guard ToolRegistry.tool(id: id) != nil else { return }
        selectedToolID = id
    }

    // MARK: Window

    /// Builds the window and shows it. The helper is already a regular app by now.
    func show() {
        let chrome = EditorChrome(session: self)
        self.chrome = chrome
        chrome.window.delegate = self
        chrome.window.makeKeyAndOrderFront(nil)
    }

    func bringForward() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closes the Editor. Nothing is asked and nothing is exported.
    func close() {
        guard !isClosing else { return }
        window?.close()
    }

    /// Esc: closes the Editor without exporting. A tool with something pending (text being
    /// typed, a crop) finishes that first, before this closes.
    func escape() {
        close()
    }

    /// Delete Capture: closes the Editor at once and has the menu bar app remove the Capture file.
    func deleteCapture() {
        // The helper may quit as this window closes, so tell the menu bar app first.
        CommandSocketClient.sendBeforeExit(
            .deleteCapture, arguments: [String(document.captureNumber)], to: AppIdentity.appSocketPath)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        isClosing = true
        onClosed?(self)
        // A button's own action may be what closed the window: free everything one run-loop
        // turn later, once that action has returned.
        DispatchQueue.main.async { [self] in
            chrome?.tearDown()
            chrome = nil
        }
    }
}

/// Delete Capture: closes the Editor at once, with no question, and removes the Capture.
struct DeleteCaptureToolbarItem: EditorToolbarItem {
    let id = "delete-capture"
    let slot = ToolbarSlot.destructive
    let order = 100
    let symbol = "trash"
    let tooltip = "Delete Capture"
    let look = ChromeButtonStyle.Look.destructive

    func perform(in session: EditorSession) {
        session.deleteCapture()
    }
}

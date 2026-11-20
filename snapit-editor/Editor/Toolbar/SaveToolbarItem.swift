/// Save: flattens the Capture and has the menu bar app write a PNG into the Save location, then
/// closes the Editor when "Close the Editor after Save" is on.
struct SaveToolbarItem: EditorToolbarItem {
    let id = "save"
    let slot = ToolbarSlot.export
    let order = 300
    let symbol = "square.and.arrow.down"
    let title: String? = "Save"
    let tooltip = "Save (⌘S)"
    let keyEquivalent: EditorKeyEquivalent? = .command("s")
    let menu: EditorMenu? = .file

    func isEnabled(in session: EditorSession) -> Bool { !session.isExporting && session.document != nil }

    func perform(in session: EditorSession) {
        session.startSave()
    }
}

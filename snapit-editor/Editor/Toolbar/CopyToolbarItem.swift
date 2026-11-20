/// Copy: flattens the Capture, puts a PNG on the pasteboard, then closes the Editor when
/// "Close the Editor after Copy" is on.
struct CopyToolbarItem: EditorToolbarItem {
    let id = "copy"
    let slot = ToolbarSlot.export
    let order = 200
    let symbol = "doc.on.doc"
    let title: String? = "Copy"
    let tooltip = "Copy (⌘C)"
    let keyEquivalent: EditorKeyEquivalent? = .command("c")
    let menu: EditorMenu? = .edit

    func isEnabled(in session: EditorSession) -> Bool { !session.isExporting && session.document != nil }

    func perform(in session: EditorSession) {
        session.startCopy()
    }
}

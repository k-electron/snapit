/// Close (⌘W): closes the Editor without exporting. It has no button; the Window menu lists it.
struct CloseToolbarItem: EditorToolbarItem {
    let id = "close"
    let slot = ToolbarSlot.menuOnly
    let order = 100
    let symbol = "xmark"
    let title: String? = "Close"
    let tooltip = "Close (⌘W)"
    let keyEquivalent: EditorKeyEquivalent? = .command("w")
    let menu: EditorMenu? = .window

    func perform(in session: EditorSession) {
        session.requestClose()
    }
}

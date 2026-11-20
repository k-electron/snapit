/// Redo (⇧⌘Z): puts back what Undo took away.
struct RedoToolbarItem: EditorToolbarItem {
    let id = "redo"
    let slot = ToolbarSlot.history
    let order = 110
    let symbol = "arrow.uturn.forward"
    let tooltip = "Redo (⇧⌘Z)"
    let keyEquivalent: EditorKeyEquivalent? = .commandShift("z")
    let menu: EditorMenu? = .edit
    let menuTitle = "Redo"

    func isEnabled(in session: EditorSession) -> Bool { session.canRedo }

    func perform(in session: EditorSession) {
        session.redo()
    }
}

/// Undo (⌘Z): takes back the last change to the Annotations.
struct UndoToolbarItem: EditorToolbarItem {
    let id = "undo"
    let slot = ToolbarSlot.history
    let order = 100
    let symbol = "arrow.uturn.backward"
    let tooltip = "Undo (⌘Z)"
    let keyEquivalent: EditorKeyEquivalent? = .command("z")
    let menu: EditorMenu? = .edit
    let menuTitle = "Undo"

    func isEnabled(in session: EditorSession) -> Bool { session.canUndo }

    func perform(in session: EditorSession) {
        session.undo()
    }
}

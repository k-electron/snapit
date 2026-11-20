/// Delete Annotation (⌫): removes the selected Annotation.
struct DeleteAnnotationToolbarItem: EditorToolbarItem {
    let id = "delete-annotation"
    let slot = ToolbarSlot.history
    let order = 120
    let symbol = "delete.left"
    let tooltip = "Delete Annotation (⌫)"
    let keyEquivalent: EditorKeyEquivalent? = .delete
    let menu: EditorMenu? = .edit
    let menuTitle = "Delete Annotation"

    func isEnabled(in session: EditorSession) -> Bool { session.canDeleteAnnotation }

    func perform(in session: EditorSession) {
        session.deleteSelectedAnnotation()
    }
}

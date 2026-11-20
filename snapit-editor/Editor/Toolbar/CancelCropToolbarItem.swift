/// Cancel Crop: leaves the Crop tool without cropping. Enabled while the Crop tool is active; Esc
/// does the same.
struct CancelCropToolbarItem: EditorToolbarItem {
    let id = "crop-cancel"
    let slot = ToolbarSlot.options
    let order = 401
    let symbol = "xmark"
    let tooltip = "Cancel Crop (Esc)"

    func isEnabled(in session: EditorSession) -> Bool { session.isCropping }

    func perform(in session: EditorSession) {
        session.cancelCrop()
    }
}

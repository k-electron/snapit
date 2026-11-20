/// Apply Crop: keeps the part of the Capture inside the crop rectangle. Enabled while the Crop
/// tool is active. Enter runs the same item, so the key and the button are one path.
struct ApplyCropToolbarItem: EditorToolbarItem {
    let id = "crop-apply"
    let slot = ToolbarSlot.options
    let order = 400
    let symbol = "checkmark"
    let tooltip = "Apply Crop (↩)"
    let look = ChromeButtonStyle.Look.prominent
    let keyEquivalent: EditorKeyEquivalent? = .enter

    func isEnabled(in session: EditorSession) -> Bool { session.isCropping }
    func isVisible(in session: EditorSession) -> Bool { session.isCropping }

    func perform(in session: EditorSession) {
        session.applyCrop()
    }
}

extension EditorKeyEquivalent {
    /// Return on its own.
    static let enter = EditorKeyEquivalent(key: "\r", modifiers: [])
}

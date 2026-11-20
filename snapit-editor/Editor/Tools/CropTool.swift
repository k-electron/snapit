import AppKit

/// Crop: shows the crop rectangle with handles on the canvas. Drag a handle to resize it, drag
/// inside it to move it, drag outside it to draw a new one. Enter (or the Apply Crop button)
/// applies it, Esc (or Cancel) leaves it as it was. The work is `EditorSession+Crop.swift`.
struct CropTool: EditorTool {
    static let toolID = "crop"

    let id = CropTool.toolID
    let order = 800
    let title = "Crop"
    let symbol = "crop"
    let key: Character? = "c"

    func pointerDown(at point: CGPoint, in session: EditorSession) {
        session.beginCropDrag(at: point)
    }

    func pointerDragged(to point: CGPoint, in session: EditorSession) {
        session.continueCropDrag(to: point)
    }

    func pointerUp(at point: CGPoint, in session: EditorSession) {
        session.finishCropDrag(at: point)
    }
}

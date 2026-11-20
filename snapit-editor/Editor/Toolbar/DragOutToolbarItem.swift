import SwiftUI

/// The drag-out thumbnail: a preview of the Capture that can be dragged into Finder or another
/// app to Export it there as a file, named like a Saved one. A click does nothing.
struct DragOutToolbarItem: EditorToolbarItem {
    let id = "drag-out"
    let slot = ToolbarSlot.export
    let order = 100
    let symbol = "photo"
    let tooltip = "Drag the Capture out as a file"

    func isEnabled(in session: EditorSession) -> Bool { session.document != nil }

    func perform(in session: EditorSession) {}

    func makeView(session: EditorSession) -> AnyView {
        AnyView(DragOutThumbnail(session: session))
    }
}

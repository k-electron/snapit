import SwiftUI

/// The eyedropper: click it, then click inside the Capture to take the color of the pixel under
/// the cursor's tip as the Annotation color. Esc or another tool ends it without picking.
struct EyedropperToolbarItem: EditorToolbarItem {
    let id = "eyedropper"
    let slot = ToolbarSlot.options
    let order = 110
    let symbol = "eyedropper"
    let tooltip = "Eyedropper: pick a color from the Capture"

    func isEnabled(in session: EditorSession) -> Bool { session.document != nil }

    func perform(in session: EditorSession) {
        session.togglePickingColor()
    }

    func makeView(session: EditorSession) -> AnyView {
        AnyView(
            Button {
                perform(in: session)
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(minWidth: 32, minHeight: 34)
            }
            .buttonStyle(ChromeButtonStyle(look: session.isPickingColor ? .selected : .plain))
            .disabled(!isEnabled(in: session))
            .help(tooltip)
            .controlMarker(tooltip))
    }
}

import SwiftUI

/// The eyedropper: click it, then click inside the Capture to take the color of the pixel under
/// the cursor's tip as the Annotation color. Esc or another tool ends it without taking one.
struct EyedropperToolbarItem: EditorToolbarItem {
    let id = "eyedropper"
    let slot = ToolbarSlot.options
    let order = 110
    let symbol = "eyedropper"
    let tooltip = "Eyedropper: take the Annotation color from the Capture"

    func isEnabled(in session: EditorSession) -> Bool { session.document != nil }

    func perform(in session: EditorSession) {
        session.toggleEyedropper()
    }

    func makeView(session: EditorSession) -> AnyView {
        AnyView(
            Button {
                perform(in: session)
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(minWidth: 28, minHeight: 34)
            }
            .buttonStyle(ChromeButtonStyle(look: session.isEyedropperActive ? .selected : .plain))
            .help(tooltip)
            .controlMarker(tooltip)
            .disabled(!isEnabled(in: session)))
    }
}

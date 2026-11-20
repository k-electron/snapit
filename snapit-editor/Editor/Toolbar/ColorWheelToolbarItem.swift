import SwiftUI

/// The color wheel button: opens the macOS color panel. Dragging in the panel recolors the
/// selected Annotation live, and the whole drag is one Undo step. The wheel shows the Annotation
/// color in its middle.
struct ColorWheelToolbarItem: EditorToolbarItem {
    let id = "color-wheel"
    let slot = ToolbarSlot.options
    let order = 120
    let symbol = "paintpalette"
    let tooltip = "Color wheel: choose any color"

    func perform(in session: EditorSession) {
        session.openColorPanel()
    }

    func isVisible(in session: EditorSession) -> Bool { !session.isCropping }

    func makeView(session: EditorSession) -> AnyView {
        let color = session.shownColor
        return AnyView(
            Button {
                perform(in: session)
            } label: {
                ZStack {
                    Circle()
                        .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                        .frame(width: 20, height: 20)
                    Circle()
                        .fill(Color(red: color.red, green: color.green, blue: color.blue))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
                .frame(minWidth: 28, minHeight: 34)
            }
            .buttonStyle(ChromeButtonStyle())
            .help(tooltip)
            .controlMarker(tooltip))
    }
}

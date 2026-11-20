import SwiftUI

/// The look of an Action bar button on macOS 26 glass. The whole tile, not just the glyph and
/// the title, is the hit area.
struct ActionBarButtonStyle: ButtonStyle {
    enum Look { case plain, prominent }

    var look: Look = .plain
    var radius: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        ActionBarButtonBody(configuration: configuration, look: look, radius: radius)
    }
}

private struct ActionBarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let look: ActionBarButtonStyle.Look
    let radius: CGFloat
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let isPressed = configuration.isPressed
        configuration.label
            .foregroundStyle(.white)
            .background(shape.fill(fill(isPressed: isPressed, isHot: isEnabled && isHovering)))
            .contentShape(shape)
            .scaleEffect(isPressed && isEnabled ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovering = $0 }
    }

    private func fill(isPressed: Bool, isHot: Bool) -> Color {
        switch look {
        case .plain: Color.white.opacity(isPressed ? 0.26 : isHot ? 0.16 : 0)
        case .prominent: Color.accentColor.opacity(isPressed ? 0.72 : isHot ? 0.92 : 1)
        }
    }
}

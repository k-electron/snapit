import SwiftUI

// The look of the Editor's toolbars: macOS 26 glass. Every button in them uses
// `ChromeButtonStyle`, whose whole tile (not just the glyph) is the hit area.

extension View {
    /// Draws the view on a glass pill of the given shape.
    func chromeGlass<S: Shape>(_ shape: S) -> some View {
        glassEffect(.regular, in: shape)
    }
}

/// Lets neighbouring glass pills blend and morph together.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) { content() }
    }
}

struct ChromeButtonStyle: ButtonStyle {
    enum Look { case plain, selected, prominent, destructive }

    var look: Look = .plain
    var radius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        ChromeButtonBody(configuration: configuration, look: look, radius: radius)
    }
}

private struct ChromeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let look: ChromeButtonStyle.Look
    let radius: CGFloat
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let isPressed = configuration.isPressed
        configuration.label
            .foregroundStyle(foreground)
            .background(shape.fill(fill(isPressed: isPressed, isHot: isEnabled && isHovering)))
            // The whole visible tile is the hit area, never just the glyph.
            .contentShape(shape)
            .scaleEffect(isPressed && isEnabled ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        switch look {
        case .selected, .prominent: .white
        case .destructive: .red
        case .plain: .primary
        }
    }

    private func fill(isPressed: Bool, isHot: Bool) -> Color {
        switch look {
        case .plain: isPressed ? .primary.opacity(0.22) : isHot ? .primary.opacity(0.11) : .clear
        case .selected: Color.accentColor.opacity(isPressed ? 0.78 : isHot ? 0.92 : 1)
        case .prominent: Color.accentColor.opacity(isPressed ? 0.72 : isHot ? 0.92 : 1)
        case .destructive: Color.red.opacity(isPressed ? 0.32 : isHot ? 0.20 : 0)
        }
    }
}

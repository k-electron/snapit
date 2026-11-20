import SwiftUI

/// Annotation color: preset swatches. A click sets the color of the selected Annotation and of the
/// ones drawn next (one Undo step), and it is remembered across launches. The ring sits centred on
/// the swatch that is the color now. Always enabled, even with nothing selected and before the
/// Capture arrives.
struct ColorSwatchesToolbarItem: EditorToolbarItem {
    let id = "annotation-color"
    let slot = ToolbarSlot.options
    let order = 100
    let symbol = "circle.fill"
    let tooltip = "Annotation color"

    /// Pressing the item picks the next swatch.
    func perform(in session: EditorSession) {
        let swatches = EditorSession.swatches
        let current = swatches.firstIndex { $0.color.hex == session.shownColor.hex } ?? -1
        session.setAnnotationColor(swatches[(current + 1) % swatches.count].color)
    }

    func makeView(session: EditorSession) -> AnyView {
        AnyView(ColorSwatchesControl(session: session))
    }
}

private struct ColorSwatchesControl: View {
    let session: EditorSession

    var body: some View {
        let shown = session.shownColor.hex
        HStack(spacing: 0) {
            ForEach(EditorSession.swatches, id: \.name) { swatch in
                SwatchButton(name: swatch.name, color: swatch.color, chosen: swatch.color.hex == shown) {
                    session.setAnnotationColor(swatch.color)
                }
            }
        }
    }
}

private struct SwatchButton: View {
    let name: String
    let color: AnnotationColor
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The ring and the dot share one centre, so the ring is centred on its swatch.
            ZStack {
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                if chosen {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2).frame(width: 22, height: 22)
                }
            }
            .frame(width: 24, height: 34)
        }
        .buttonStyle(ChromeButtonStyle())
        .help(name)
        .controlMarker(name)
    }
}

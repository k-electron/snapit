import SwiftUI

/// Text size: three presets, for the selected Text, the one being typed and the next ones. Every
/// tile is a full-size button with its tooltip. Disabled for an Arrow, a shape or a Highlighter.
struct TextSizeToolbarItem: EditorToolbarItem {
    let id = "text-size"
    let slot = ToolbarSlot.options
    let order = 210
    let symbol = "textformat.size"
    let tooltip = "Text size"

    func isEnabled(in session: EditorSession) -> Bool { session.textSizeApplies }

    /// Pressing the item picks the next size.
    func perform(in session: EditorSession) {
        let sizes = EditorSession.textSizes
        let current = sizes.firstIndex { abs($0 - session.shownTextSize) < 0.5 } ?? -1
        session.setAnnotationTextSize(sizes[(current + 1) % sizes.count])
    }

    func makeView(session: EditorSession) -> AnyView {
        AnyView(TextSizeControl(session: session))
    }
}

private struct TextSizeControl: View {
    let session: EditorSession

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(EditorSession.textSizes.enumerated()), id: \.offset) { index, size in
                let chosen = abs(session.shownTextSize - size) < 0.5
                let tooltip = "Text size: \(Int(size)) pt"
                Button {
                    session.setAnnotationTextSize(size)
                } label: {
                    Text("A")
                        .font(.system(size: [11, 14, 18][index % 3], weight: .semibold))
                        .frame(minWidth: 26, minHeight: 34)
                }
                .buttonStyle(ChromeButtonStyle(look: chosen && session.textSizeApplies ? .selected : .plain))
                .help(tooltip)
                .controlMarker(tooltip)
            }
        }
        .disabled(!session.textSizeApplies)
    }
}

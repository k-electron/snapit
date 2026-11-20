import SwiftUI

/// Width: three presets, for the selected Arrow, Rectangle outline or Oval outline and for the
/// next ones, or for the Highlighter's thickness (each remembered apart). Every tile is a
/// full-size button with its tooltip. Disabled for a Text, which has a text size instead.
struct WidthToolbarItem: EditorToolbarItem {
    let id = "annotation-width"
    let slot = ToolbarSlot.options
    let order = 200
    let symbol = "lineweight"
    let tooltip = "Width"

    func isEnabled(in session: EditorSession) -> Bool { session.widthApplies }

    /// Pressing the item picks the next preset.
    func perform(in session: EditorSession) {
        let presets = session.activeWidthChoice.presets
        guard !presets.isEmpty else { return }
        let current = presets.firstIndex { abs($0 - session.shownWidth) < 0.5 } ?? -1
        session.setAnnotationWidth(presets[(current + 1) % presets.count])
    }

    func makeView(session: EditorSession) -> AnyView {
        AnyView(WidthControl(session: session))
    }
}

private struct WidthControl: View {
    let session: EditorSession

    var body: some View {
        // A control never changes size, so it always has three tiles (the line presets while
        // nothing applies).
        let choice = session.activeWidthChoice
        let presets = choice == .none ? WidthChoice.line.presets : choice.presets
        HStack(spacing: 2) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, width in
                let chosen = abs(session.shownWidth - width) < 0.5
                let tooltip = "Width: \(Int(width)) pt"
                Button {
                    session.setAnnotationWidth(width)
                } label: {
                    RoundedRectangle(cornerRadius: 1.5)
                        .frame(width: 16, height: min(max(width * (choice == .highlighter ? 0.3 : 1), 2), 10))
                        .frame(minWidth: 30, minHeight: 34)
                }
                .buttonStyle(ChromeButtonStyle(look: chosen && choice != .none ? .selected : .plain))
                .help(tooltip)
                .controlMarker(tooltip)
            }
        }
        .disabled(!session.widthApplies)
    }
}

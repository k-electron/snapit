import SwiftUI

/// Size: three presets that are widths for the selected Arrow, Rectangle outline, Oval outline or
/// Highlighter (and the next ones), and text sizes for a Text. The two never apply together, so one
/// control of three tiles serves both and the toolbar stays narrow. The line width and the
/// Highlighter's thickness have their own presets and are remembered apart. Every tile is a
/// full-size button with its tooltip.
struct SizeToolbarItem: EditorToolbarItem {
    let id = "annotation-size"
    let slot = ToolbarSlot.options
    let order = 200
    let symbol = "lineweight"
    let tooltip = "Width and text size"

    func isEnabled(in session: EditorSession) -> Bool { session.sizeControlApplies }

    /// Pressing the item picks the next preset.
    func perform(in session: EditorSession) {
        if session.sizeControlIsTextSize {
            let sizes = EditorSession.textSizes
            let current = sizes.firstIndex { abs($0 - session.shownTextSize) < 0.5 } ?? -1
            session.setAnnotationTextSize(sizes[(current + 1) % sizes.count])
        } else {
            let presets = session.activeWidthChoice.presets
            guard !presets.isEmpty else { return }
            let current = presets.firstIndex { abs($0 - session.shownWidth) < 0.5 } ?? -1
            session.setAnnotationWidth(presets[(current + 1) % presets.count])
        }
    }

    func makeView(session: EditorSession) -> AnyView {
        AnyView(SizeControl(session: session))
    }
}

private struct SizeControl: View {
    let session: EditorSession

    var body: some View {
        // Always three tiles, so the control never changes size (the line presets while nothing applies).
        let isText = session.sizeControlIsTextSize
        let choice = session.activeWidthChoice
        let presets = isText ? EditorSession.textSizes : (choice == .none ? WidthChoice.line.presets : choice.presets)
        HStack(spacing: 2) {
            ForEach(Array(presets.enumerated()), id: \.offset) { index, size in
                let shown = isText ? session.shownTextSize : session.shownWidth
                let chosen = abs(shown - size) < 0.5 && session.sizeControlApplies
                let tooltip = isText ? "Text size: \(Int(size)) pt" : "Width: \(Int(size)) pt"
                Button {
                    if isText { session.setAnnotationTextSize(size) } else { session.setAnnotationWidth(size) }
                } label: {
                    Group {
                        if isText {
                            Text("A").font(.system(size: [11, 14, 18][index % 3], weight: .semibold))
                        } else {
                            RoundedRectangle(cornerRadius: 1.5)
                                .frame(width: 16, height: min(max(size * (choice == .highlighter ? 0.3 : 1), 2), 10))
                        }
                    }
                    .frame(minWidth: 26, minHeight: 34)
                }
                .buttonStyle(ChromeButtonStyle(look: chosen ? .selected : .plain))
                .help(tooltip)
                .controlMarker(tooltip)
            }
        }
        .disabled(!session.sizeControlApplies)
    }
}
